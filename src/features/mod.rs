//! One folder/file per feature. Each feature owns its UI, its state and its SQL,
//! and never imports another feature; the shell in `app.rs` wires them together.

pub mod add_task;
pub mod edit_task;
pub mod filters;
pub mod settings;
pub mod task_list;
