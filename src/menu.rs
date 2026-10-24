//! Menu bar and app-wide keyboard shortcuts. On macOS this is the native menu
//! bar; elsewhere the same commands are bound to keyboard shortcuts inside egui.

/// App-specific commands the shell reacts to. Window commands (close, minimise,
/// full screen) are native menu items and never reach the app.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Command {
    NewTask,
    Find,
    Settings,
    ToggleSidebar,
}

#[cfg(target_os = "macos")]
mod imp {
    use std::sync::mpsc::{self, Receiver};

    use eframe::egui;
    use muda::accelerator::{Accelerator, Code, Modifiers};
    use muda::{Menu as NativeMenu, MenuEvent, MenuId, MenuItem, PredefinedMenuItem, Submenu};

    use super::Command;

    pub struct Menu {
        _menu: Option<NativeMenu>,
        toggle_sidebar: MenuItem,
        commands: Vec<(MenuId, Command)>,
        events: Receiver<MenuId>,
    }

    fn item(label: &str, modifiers: Modifiers, code: Code) -> MenuItem {
        MenuItem::new(label, true, Some(Accelerator::new(modifiers, code)))
    }

    fn build(
        new_task: &MenuItem,
        find: &MenuItem,
        settings: &MenuItem,
        toggle_sidebar: &MenuItem,
    ) -> muda::Result<NativeMenu> {
        let app = Submenu::with_items(
            "Tickoff",
            true,
            &[
                &PredefinedMenuItem::about(Some("About Tickoff"), None),
                &PredefinedMenuItem::separator(),
                settings,
                &PredefinedMenuItem::separator(),
                &PredefinedMenuItem::services(None),
                &PredefinedMenuItem::separator(),
                &PredefinedMenuItem::hide(None),
                &PredefinedMenuItem::hide_others(None),
                &PredefinedMenuItem::show_all(None),
                &PredefinedMenuItem::separator(),
                &PredefinedMenuItem::quit(None),
            ],
        )?;
        let file = Submenu::with_items(
            "File",
            true,
            &[
                new_task,
                &PredefinedMenuItem::separator(),
                &PredefinedMenuItem::close_window(None),
            ],
        )?;
        let view = Submenu::with_items(
            "View",
            true,
            &[
                toggle_sidebar,
                find,
                &PredefinedMenuItem::separator(),
                &PredefinedMenuItem::fullscreen(None),
            ],
        )?;
        let window = Submenu::with_items(
            "Window",
            true,
            &[
                &PredefinedMenuItem::minimize(None),
                &PredefinedMenuItem::maximize(None),
                &PredefinedMenuItem::separator(),
                &PredefinedMenuItem::bring_all_to_front(None),
            ],
        )?;

        let menu = NativeMenu::with_items(&[&app, &file, &view, &window])?;
        menu.init_for_nsapp();
        window.set_as_windows_menu_for_nsapp();
        Ok(menu)
    }

    impl Menu {
        /// Must run on the main thread after the event loop has started.
        pub fn install(ctx: &egui::Context) -> Self {
            let new_task = item("New Task", Modifiers::META, Code::KeyN);
            let find = item("Find Tasks", Modifiers::META, Code::KeyF);
            let settings = item("Settings…", Modifiers::META, Code::Comma);
            let toggle_sidebar = item(
                "Hide Sidebar",
                Modifiers::META | Modifiers::CONTROL,
                Code::KeyS,
            );

            let menu = match build(&new_task, &find, &settings, &toggle_sidebar) {
                Ok(menu) => Some(menu),
                Err(error) => {
                    eprintln!("could not build the menu bar: {error}");
                    None
                }
            };

            let (sender, events) = mpsc::channel();
            let ctx = ctx.clone();
            MenuEvent::set_event_handler(Some(move |event: MenuEvent| {
                let _ = sender.send(event.id);
                ctx.request_repaint();
            }));

            Self {
                _menu: menu,
                commands: vec![
                    (toggle_sidebar.id().clone(), Command::ToggleSidebar),
                    (new_task.id().clone(), Command::NewTask),
                    (find.id().clone(), Command::Find),
                    (settings.id().clone(), Command::Settings),
                ],
                toggle_sidebar,
                events,
            }
        }

        pub fn set_sidebar_visible(&self, visible: bool) {
            self.toggle_sidebar.set_text(if visible {
                "Hide Sidebar"
            } else {
                "Show Sidebar"
            });
        }

        pub fn poll(&self, _ctx: &egui::Context) -> Vec<Command> {
            self.events
                .try_iter()
                .filter_map(|id| {
                    self.commands
                        .iter()
                        .find(|(c, _)| *c == id)
                        .map(|(_, cmd)| *cmd)
                })
                .collect()
        }
    }
}

#[cfg(not(target_os = "macos"))]
mod imp {
    use eframe::egui::{self, Key, KeyboardShortcut, Modifiers};

    use super::Command;

    const SHORTCUTS: [(KeyboardShortcut, Command); 4] = [
        (
            KeyboardShortcut::new(Modifiers::COMMAND, Key::N),
            Command::NewTask,
        ),
        (
            KeyboardShortcut::new(Modifiers::COMMAND, Key::F),
            Command::Find,
        ),
        (
            KeyboardShortcut::new(Modifiers::COMMAND, Key::Comma),
            Command::Settings,
        ),
        (
            KeyboardShortcut::new(Modifiers::COMMAND | Modifiers::ALT, Key::S),
            Command::ToggleSidebar,
        ),
    ];

    pub struct Menu;

    impl Menu {
        pub fn install(_ctx: &egui::Context) -> Self {
            Self
        }

        pub fn set_sidebar_visible(&self, _visible: bool) {}

        pub fn poll(&self, ctx: &egui::Context) -> Vec<Command> {
            ctx.input_mut(|i| {
                SHORTCUTS
                    .iter()
                    .filter(|(shortcut, _)| i.consume_shortcut(shortcut))
                    .map(|(_, command)| *command)
                    .collect()
            })
        }
    }
}

pub use imp::Menu;
