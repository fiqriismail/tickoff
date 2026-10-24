//! The application shell: owns the connection and the loaded tasks, lays out
//! the screen, and routes what each feature reports back. No feature logic lives here.

use eframe::egui::{self, Align, CentralPanel, Frame, Layout, Margin, Panel};
use rusqlite::Connection;

use crate::features::add_task::AddTask;
use crate::features::edit_task::EditTask;
use crate::features::filters::Filters;
use crate::features::settings::Settings;
use crate::features::task_list::{self, TaskList};
use crate::shared::outcome::Outcome;
use crate::shared::task::Task;
use crate::shared::{db, theme};

#[derive(Clone, Copy, PartialEq, Eq)]
enum View {
    Tasks,
    Settings,
}

pub struct App {
    conn: Connection,
    tasks: Vec<Task>,
    error: Option<String>,
    view: View,
    filters: Filters,
    add_task: AddTask,
    task_list: TaskList,
    edit_task: EditTask,
    settings: Settings,
}

impl App {
    pub fn new(cc: &eframe::CreationContext<'_>) -> rusqlite::Result<Self> {
        let conn = db::open()?;
        let settings = Settings::load(&conn)?;
        theme::apply(&cc.egui_ctx, settings.appearance());

        let mut app = Self {
            conn,
            tasks: Vec::new(),
            error: None,
            view: View::Tasks,
            filters: Filters::new(),
            add_task: AddTask::new(),
            task_list: TaskList::new(),
            edit_task: EditTask::new(),
            settings,
        };
        app.reload();
        Ok(app)
    }

    fn reload(&mut self) {
        match task_list::load_all(&self.conn) {
            Ok(tasks) => self.tasks = tasks,
            Err(e) => self.error = Some(e.to_string()),
        }
    }

    fn handle(&mut self, outcome: Outcome) {
        self.error = match outcome {
            Outcome::Changed => None,
            Outcome::Failed(message) => Some(message),
        };
        self.reload();
    }

    fn sidebar(&mut self, ui: &mut egui::Ui) {
        ui.with_layout(Layout::bottom_up(Align::Min), |ui| {
            if self.settings.nav_row(ui, self.view == View::Settings).clicked() {
                self.view = View::Settings;
            }

            ui.with_layout(Layout::top_down(Align::Min), |ui| {
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
        ui.add_space(6.0);

        if let Some(outcome) = self.add_task.show(ui, &self.conn) {
            self.handle(outcome);
        }

        self.error_banner(ui);

        let event = self
            .task_list
            .show(ui, &self.conn, &self.tasks, |t| filter.matches(t));
        match event {
            Some(task_list::Event::Edit(task)) => self.edit_task.open(task),
            Some(task_list::Event::Outcome(outcome)) => self.handle(outcome),
            None => {}
        }
    }

    fn settings_page(&mut self, ui: &mut egui::Ui) {
        self.error_banner(ui);
        if let Some(outcome) = self.settings.show(ui, &self.conn) {
            self.handle(outcome);
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
        let p = theme::palette(ui.ctx());

        Panel::left("sidebar")
            .exact_size(230.0)
            .resizable(false)
            .show_separator_line(false)
            .frame(Frame::new().fill(p.sidebar).inner_margin(Margin::same(18)))
            .show(ui, |ui| self.sidebar(ui));

        CentralPanel::default()
            .frame(Frame::new().fill(p.bg).inner_margin(Margin::symmetric(28, 22)))
            .show(ui, |ui| self.main_panel(ui));

        if let Some(outcome) = self.edit_task.show(&ui.ctx().clone(), &self.conn) {
            self.handle(outcome);
        }
    }
}
