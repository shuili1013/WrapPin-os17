//! iOS 17.4–17.x location path.
//!
//! iOS 17 does not offer the network remote-pairing service that WrapPin uses
//! on iOS 18+, but from 17.4 lockdown can start `CoreDeviceProxy`, which opens
//! the same CDTunnel that carries RSD. This module connects through the
//! device-tunnel app (LocalDevVPN, default 10.7.0.1) with a classic lockdown
//! pairing file (`.mobiledevicepairing`, the same kind SideStore uses), makes
//! sure the personalized Developer Disk Image is mounted, then hands the tunnel
//! to the shared RSD/DVT location loop.

use std::ffi::c_char;
use std::net::IpAddr;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use idevice::IdeviceService;
use idevice::core_device_proxy::CoreDeviceProxy;
use idevice::heartbeat::HeartbeatClient;
use idevice::lockdown::LockdownClient;
use idevice::mobile_image_mounter::ImageMounter;
use idevice::pairing_file::PairingFile;
use idevice::provider::{IdeviceProvider, TcpProvider};
use tokio::time::timeout;

use crate::{
    LocationCoordinates, LocationError, LocationStage as Stage, LocationStartedCallback,
    connection_step, current_coordinates, drive_location_over_rsd,
};

/// Uploading ~20 MB through the device tunnel and asking Apple's TSS server
/// for a personalization ticket takes far longer than a normal step.
const DDI_MOUNT_TIMEOUT: Duration = Duration::from_secs(180);

pub(crate) struct LockdownSessionInput {
    pub pairing_file: Vec<u8>,
    pub peer_address: String,
    pub ddi_directory: Option<String>,
    pub coordinates: Arc<Mutex<LocationCoordinates>>,
    pub started_callback: LocationStartedCallback,
    pub callback_context: usize,
    pub cancellation: Arc<AtomicBool>,
}

pub(crate) async fn run_lockdown_location_session(
    input: LockdownSessionInput,
) -> Result<(), LocationError> {
    let cancellation = input.cancellation;
    let applied_coordinates = current_coordinates(&input.coordinates)?;

    let pairing_file = PairingFile::from_bytes(&input.pairing_file).map_err(|_| {
        LocationError::new(
            Stage::PairingRecord,
            "The pairing file could not be read. Import the .mobiledevicepairing file again.",
        )
    })?;
    let peer_ip: IpAddr = input.peer_address.parse().map_err(|_| {
        LocationError::new(
            Stage::VpnConnection,
            "The device tunnel returned an invalid device address.",
        )
    })?;
    let provider = TcpProvider {
        addr: peer_ip,
        scope_id: None,
        pairing_file,
        label: "WrapPin".to_string(),
    };

    // Lockdown services reached over the network stop answering unless a
    // heartbeat keeps the connection alive, so start it before anything else.
    let mut heartbeat = connection_step(
        &cancellation,
        HeartbeatClient::connect(&provider),
        LocationError::recoverable(
            Stage::VpnConnection,
            "The device tunnel did not make the iPhone connection available in time.",
        ),
        LocationError::recoverable(
            Stage::VpnConnection,
            "WrapPin could not reach the iPhone through the device tunnel. Check that LocalDevVPN is connected.",
        ),
    )
    .await?;
    let heartbeat_cancel = Arc::clone(&cancellation);
    let heartbeat_task = tokio::spawn(async move {
        let mut interval = 15;
        while !heartbeat_cancel.load(Ordering::Acquire) {
            match heartbeat.get_marco(interval).await {
                Ok(next) => interval = next + 5,
                Err(_) => break,
            }
            if heartbeat.send_polo().await.is_err() {
                break;
            }
        }
    });

    let outcome = async {
        ensure_developer_disk_image(&provider, input.ddi_directory.as_deref(), &cancellation)
            .await?;

        let proxy = connection_step(
            &cancellation,
            CoreDeviceProxy::connect(&provider),
            LocationError::new(
                Stage::TunnelCreation,
                "The iPhone did not create its developer tunnel in time.",
            ),
            LocationError::new(
                Stage::TunnelCreation,
                "The iPhone could not create its developer tunnel. iOS 17.4 or later and Developer Mode are required.",
            ),
        )
        .await?;
        let rsd_port = proxy.tunnel_info().server_rsd_port;
        let adapter = proxy.create_software_tunnel().map_err(|error| {
            LocationError::new(
                Stage::TunnelSecurity,
                "WrapPin could not start the developer tunnel.",
            )
            .with_detail(&error)
        })?;

        drive_location_over_rsd(
            adapter.to_async_handle(),
            rsd_port,
            applied_coordinates,
            input.coordinates,
            input.started_callback,
            input.callback_context,
            Arc::clone(&cancellation),
        )
        .await
    }
    .await;

    heartbeat_task.abort();
    outcome
}

/// Mounts the personalized DDI when nothing is mounted yet. iOS 17 drops the
/// image on every reboot, and DVT services do not exist without it.
async fn ensure_developer_disk_image(
    provider: &TcpProvider,
    ddi_directory: Option<&str>,
    cancellation: &Arc<AtomicBool>,
) -> Result<(), LocationError> {
    let mut mounter = connection_step(
        cancellation,
        ImageMounter::connect(provider),
        LocationError::new(
            Stage::LocationService,
            "The iPhone's disk image service did not respond in time.",
        ),
        LocationError::new(
            Stage::LocationService,
            "WrapPin could not open the iPhone's disk image service.",
        ),
    )
    .await?;
    let mounted = connection_step(
        cancellation,
        mounter.copy_devices(),
        LocationError::new(
            Stage::LocationService,
            "The iPhone did not list its disk images in time.",
        ),
        LocationError::new(
            Stage::LocationService,
            "WrapPin could not list the iPhone's disk images.",
        ),
    )
    .await?;
    if !mounted.is_empty() {
        return Ok(());
    }

    let directory = ddi_directory.map(PathBuf::from).ok_or(LocationError::new(
        Stage::LocationService,
        "The Developer Disk Image is not mounted and has not been downloaded yet. Download it in Device Setup first.",
    ))?;
    let read = |name: &str| {
        let path = directory.join(name);
        async move { tokio::fs::read(path).await }
    };
    let missing = || {
        LocationError::new(
            Stage::LocationService,
            "The downloaded Developer Disk Image is incomplete. Download it again in Device Setup.",
        )
    };
    let image = read("Image.dmg").await.map_err(|_| missing())?;
    let trust_cache = read("Image.dmg.trustcache").await.map_err(|_| missing())?;
    let build_manifest = read("BuildManifest.plist").await.map_err(|_| missing())?;

    let unique_chip_id = read_unique_chip_id(provider, cancellation).await?;

    if cancellation.load(Ordering::Acquire) {
        return Err(LocationError::cancelled());
    }
    tokio::select! {
        outcome = timeout(
            DDI_MOUNT_TIMEOUT,
            mounter.mount_personalized(
                provider,
                image,
                trust_cache,
                &build_manifest,
                None,
                unique_chip_id,
            ),
        ) => {
            outcome
                .map_err(|_| LocationError::new(
                    Stage::LocationService,
                    "Mounting the Developer Disk Image took too long.",
                ))?
                .map_err(|error| LocationError::new(
                    Stage::LocationService,
                    "The iPhone did not accept the Developer Disk Image. Check the internet connection and Developer Mode.",
                ).with_detail(&error))
        }
        _ = crate::wait_for_cancellation(Arc::clone(cancellation)) => Err(LocationError::cancelled()),
    }
}

async fn read_unique_chip_id(
    provider: &TcpProvider,
    cancellation: &Arc<AtomicBool>,
) -> Result<u64, LocationError> {
    let mut lockdown = connection_step(
        cancellation,
        LockdownClient::connect(provider),
        LocationError::new(
            Stage::PairVerification,
            "The iPhone did not respond in time.",
        ),
        LocationError::recoverable(
            Stage::PairVerification,
            "WrapPin could not reach the iPhone's lockdown service.",
        ),
    )
    .await?;
    let pairing_file = provider.get_pairing_file().await.map_err(|error| {
        LocationError::new(Stage::PairingRecord, "The pairing file could not be read.")
            .with_detail(&error)
    })?;
    connection_step(
        cancellation,
        lockdown.start_session(&pairing_file),
        LocationError::new(
            Stage::PairVerification,
            "Pairing verification took too long.",
        ),
        LocationError::new(
            Stage::PairVerification,
            "The iPhone rejected the pairing file. Create a new one with your computer.",
        ),
    )
    .await?;
    let value = connection_step(
        cancellation,
        lockdown.get_value(Some("UniqueChipID"), None),
        LocationError::new(
            Stage::PairVerification,
            "The iPhone did not respond in time.",
        ),
        LocationError::new(
            Stage::PairVerification,
            "WrapPin could not read the iPhone's chip identifier.",
        ),
    )
    .await?;
    value.as_unsigned_integer().ok_or(LocationError::new(
        Stage::PairVerification,
        "The iPhone returned an unexpected chip identifier.",
    ))
}

/// Reads an optional, non-empty C string.
pub(crate) unsafe fn optional_path(value: *const c_char) -> Option<String> {
    if value.is_null() {
        return None;
    }
    let text = unsafe { std::ffi::CStr::from_ptr(value) }
        .to_str()
        .ok()?
        .trim();
    (!text.is_empty()).then(|| text.to_string())
}
