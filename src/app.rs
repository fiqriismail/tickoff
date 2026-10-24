//! The application shell: owns the connection and the loaded tasks, lays out
//! the screen, and routes what each feature reports back. No feature logic lives here.

use eframe::egui::{
    self, Align, CentralPanel, Frame, Id, Layout, Margin, Panel, PointerButton, Rect, Sense,
    ViewportCommand, vec2,
};
use rusqlite::Connection;

use crate::features::add_task::AddTask;
use crate::features::edit_task::EditTask;
use crate::features::filters::Filters;
use crate::features::settings::Settings;
use crate::features::task_list::{self, TaskList};
use crate::menu::{self, Command};
use crate::shared::outcome::Outcome;
use crate::shared::tasks::{self, TaskSet};
use crate::shared::{db, theme};

/// Height of the invisible strip along the top edge that drags the window.
const TITLE_BAR_HEIGHT: f32 = 18.0;
/// Room above the sidebar content for the macOS close/minimise/zoom buttons.
const TRAFFIC_LIGHT_INSET: f32 = 22.0;
/// Gap between the top of the window and the main page content.
const PAGE_TOP_MARGIN: f32 = 22.0;

const SIDEBAR_WIDTH: f32 = 230.0;
const SIDEBAR_MIN_WIDTH: f32 = 200.0;
const SIDEBAR_MAX_WIDTH: f32 = 320.0;

#[derive(Clone, Copy, PartialEq, Eq)]
enum View {
    Tasks,
    Settings,
}

pub struct App {
    conn: Connection,
    tasks: TaskSet,
    error: Option<String>,
    view: View,
    filters: Filters,
    add_task: AddTask,
    task_list: TaskList,
    edit_task: EditTask,
    settings: Settings,
    menu: menu::Menu,
    sidebar_visible: bool,
}

impl App {
    pub fn new(
        cc: &eframe::CreationContext<'_>,
    ) -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        let conn = db::open()?;
        let settings = Settings::load(&conn)?;
        theme::apply(&cc.egui_ctx, settings.appearance());

        let mut app = Self {
            conn,
            tasks: TaskSet::new(),
            error: None,
            view: View::Tasks,
            filters: Filters::new(),
            add_task: AddTask::new(),
            task_list: TaskList::new(),
            edit_task: EditTask::new(),
            settings,
            menu: menu::Menu::install(&cc.egui_ctx),
            sidebar_visible: true,
        };
        app.reload();
        Ok(app)
    }

    fn reload(&mut self) {
        match tasks::load_all(&self.conn) {
            Ok(tasks) => self.tasks.replace(tasks),
            Err(e) => self.error = Some(e.to_string()),
        }
    }

    /// Records the outcome of a task change and reloads the tasks.
    fn handle(&mut self, outcome: Outcome) {
        self.report(outcome);
        self.reload();
    }

    /// Records an outcome that did not touch the tasks table, so no reload is needed.
    fn report(&mut self, outcome: Outcome) {
        self.error = match outcome {
            Outcome::Changed => None,
            Outcome::Failed(message) => Some(message),
        };
    }

    fn run(&mut self, command: Command) {
        match command {
            Command::NewTask => {
                self.view = View::Tasks;
                self.add_task.focus();
            }
            Command::Find => {
                self.view = View::Tasks;
                self.task_list.focus_search();
            }
            Command::Settings => self.view = View::Settings,
            Command::ToggleSidebar => {
                self.sidebar_visible = !self.sidebar_visible;
                self.menu.set_sidebar_visible(self.sidebar_visible);
            }
        }
    }

    fn sidebar(&mut self, ui: &mut egui::Ui) {
        ui.with_layout(Layout::bottom_up(Align::Min), |ui| {
            if self
                .settings
                .nav_row(ui, self.view == View::Settings)
                .clicked()
            {
                self.view = View::Settings;
            }

            ui.with_layout(Layout::top_down(Align::Min), |ui| {
                ui.add_space(TRAFFIC_LIGHT_INSET);
                let output =
                    self.filters
                        .show(ui, &self.conn, &self.tasks, self.view == View::Tasks);
                if output.row_clicked {
                    self.view = View::Tasks;
                }
                if let Some(outcome) = output.outcome {
                    self.handle(outcome);
                }
            });
        });
    }

    fn main_panel(&mut self, ui: &mut egui::Ui) {
        match self.view {
            View::Tasks => self.tasks_page(ui),
            View::Settings => self.settings_page(ui),
        }
    }

    fn tasks_page(&mut self, ui: &mut egui::Ui) {
        let filter = self.filters.selected();
        self.task_list.header(ui, filter.label());
        ui.add_space(14.0);

        if let Some(outcome) = self.add_task.show(ui, &self.conn) {
            self.handle(outcome);
        }

        self.error_banner(ui);
        ui.add_space(8.0);

        let event = self
            .task_list
            .show(ui, &self.conn, &self.tasks, filter.status());
        match event {
            Some(task_list::Event::Edit(task)) => self.edit_task.open(task),
            Some(task_list::Event::Outcome(outcome)) => self.handle(outcome),
            None => {}
        }
    }

    fn settings_page(&mut self, ui: &mut egui::Ui) {
        self.error_banner(ui);
        if let Some(outcome) = self.settings.show(ui, &self.conn) {
            self.report(outcome);
        }
    }

    fn error_banner(&self, ui: &mut egui::Ui) {
        if let Some(error) = &self.error {
            let red = theme::palette(ui.ctx()).red;
            ui.colored_label(red, format!("Database error: {error}"));
        }
    }
}

impl eframe::App for App {
    fn ui(&mut self, ui: &mut egui::Ui, _frame: &mut eframe::Frame) {
        for command in self.menu.poll(ui.ctx()) {
            self.run(command);
        }

        let p = theme::palette(ui.ctx());

        if self.sidebar_visible {
            Panel::left("sidebar")
                .default_size(SIDEBAR_WIDTH)
                .size_range(SIDEBAR_MIN_WIDTH..=SIDEBAR_MAX_WIDTH)
                .resizable(true)
                .show_separator_line(false)
                .frame(Frame::new().fill(p.sidebar).inner_margin(Margin::same(18)))
                .show(ui, |ui| self.sidebar(ui));
        }

        // Without the sidebar the traffic lights sit over the page, so make room for them.
        let top = if self.sidebar_visible {
            PAGE_TOP_MARGIN
        } else {
            PAGE_TOP_MARGIN + TRAFFIC_LIGHT_INSET
        };
        CentralPanel::default()
            .frame(Frame::new().fill(p.bg).inner_margin(Margin {
                left: 28,
                right: 28,
                top: 0,
                bottom: 22,
            }))
            .show(ui, |ui| {
                ui.add_space(top);
                self.main_panel(ui);
            });

        if let Some(outcome) = self.edit_task.show(&ui.ctx().clone(), &self.conn) {
            self.handle(outcome);
        }

        title_bar_drag_area(ui);
    }
}

/// With a transparent title bar nothing drags the window any more, so an
/// invisible strip along the top does it, and double-click zooms like macOS.
fn title_bar_drag_area(ui: &mut egui::Ui) {
    let full = ui.max_rect();
    let strip = Rect::from_min_size(full.min, vec2(full.width(), TITLE_BAR_HEIGHT));
    let response = ui.interact(
        strip,
        Id::unique("tickoff::title_bar"),
        Sense::click_and_drag(),
    );

    let ctx = ui.ctx();
    if response.double_clicked() {
        let maximized = ctx.input(|i| i.viewport().maximized.unwrap_or(false));
        ctx.send_viewport_cmd(ViewportCommand::Maximized(!maximized));
    } else if response.drag_started_by(PointerButton::Primary) {
        ctx.send_viewport_cmd(ViewportCommand::StartDrag);
    }
}
