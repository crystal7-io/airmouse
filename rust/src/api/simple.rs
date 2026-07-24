use enigo::{Button, Coordinate, Direction, Enigo, Mouse, Settings};
use lazy_static::lazy_static;
use std::sync::Mutex;
use std::time::{Duration, Instant};

struct AirMouseState {
    enigo: Enigo,
    left_pressed: bool,
    right_pressed: bool,
    suppress_motion_until: Option<Instant>,
}

lazy_static! {
    static ref STATE: Mutex<Option<AirMouseState>> = Mutex::new(None);
}

const CLICK_SUPPRESSION: Duration = Duration::from_millis(30);

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    if let Ok(enigo_instance) = Enigo::new(&Settings::default()) {
        let mut state = STATE.lock().unwrap();
        *state = Some(AirMouseState {
            enigo: enigo_instance,
            left_pressed: false,
            right_pressed: false,
            suppress_motion_until: None,
        });
    }
}

pub fn process_ble_payload(payload: Vec<u8>) {
    if payload.len() < 6 {
        return;
    }

    let mut state_guard = STATE.lock().unwrap();
    if let Some(state) = state_guard.as_mut() {
        let dx = i16::from_le_bytes([payload[0], payload[1]]) as i32;
        let dy = i16::from_le_bytes([payload[2], payload[3]]) as i32;

        let left_is_pressed = payload[4] == 1;
        let right_is_pressed = payload[5] == 1;

        // If either button changes state, suppress motion briefly to avoid
        // accidental drags caused by hand movement while clicking.
        let left_changed = left_is_pressed != state.left_pressed;
        let right_changed = right_is_pressed != state.right_pressed;

        if left_changed || right_changed {
            state.suppress_motion_until =
                Some(Instant::now() + CLICK_SUPPRESSION);
        }

        let suppress_motion = state
            .suppress_motion_until
            .map(|until| Instant::now() < until)
            .unwrap_or(false);

        if !suppress_motion && (dx != 0 || dy != 0) {
            let _ = state.enigo.move_mouse(dx, dy, Coordinate::Rel);
        }

        // Handle left button
        if left_is_pressed && !state.left_pressed {
            let _ = state.enigo.button(Button::Left, Direction::Press);
            state.left_pressed = true;
        } else if !left_is_pressed && state.left_pressed {
            let _ = state.enigo.button(Button::Left, Direction::Release);
            state.left_pressed = false;
        }

        // Handle right button
        if right_is_pressed && !state.right_pressed {
            let _ = state.enigo.button(Button::Right, Direction::Press);
            state.right_pressed = true;
        } else if !right_is_pressed && state.right_pressed {
            let _ = state.enigo.button(Button::Right, Direction::Release);
            state.right_pressed = false;
        }
    }
}