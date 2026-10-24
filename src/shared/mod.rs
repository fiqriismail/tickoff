//! Cross-cutting building blocks used by more than one feature.
//!
//! Keep this small: something belongs here only when two or more features
//! genuinely need it. Everything else lives inside the feature that uses it.

pub mod db;
pub mod outcome;
pub mod task;
pub mod theme;
pub mod widgets;
