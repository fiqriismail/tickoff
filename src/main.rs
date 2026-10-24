mod app;
mod features;
mod shared;

use eframe::egui;

fn main() -> eframe::Result {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_title("Tasks")
            .with_inner_size([1040.0, 720.0])
            .with_min_inner_size([760.0, 480.0]),
        ..Default::default()
    };

    eframe::run_native(
        "Tasks",
        options,
        Box::new(|cc| Ok(Box::new(app::App::new(cc)?))),
    )
}
