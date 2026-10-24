use chrono::NaiveDate;

pub const DATE_FORMAT: &str = "%Y-%m-%d";

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Status {
    Todo,
    InProgress,
    Done,
}

impl Status {
    pub const ALL: [Status; 3] = [Status::Todo, Status::InProgress, Status::Done];

    pub fn label(self) -> &'static str {
        match self {
            Status::Todo => "To do",
            Status::InProgress => "In progress",
            Status::Done => "Done",
        }
    }

    pub fn next(self) -> Status {
        match self {
            Status::Todo => Status::InProgress,
            Status::InProgress => Status::Done,
            Status::Done => Status::Todo,
        }
    }

    pub fn to_db(self) -> i64 {
        match self {
            Status::Todo => 0,
            Status::InProgress => 1,
            Status::Done => 2,
        }
    }

    pub fn from_db(value: i64) -> Status {
        match value {
            1 => Status::InProgress,
            2 => Status::Done,
            _ => Status::Todo,
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Priority {
    Low,
    Medium,
    High,
}

impl Priority {
    pub const ALL: [Priority; 3] = [Priority::Low, Priority::Medium, Priority::High];

    pub fn label(self) -> &'static str {
        match self {
            Priority::Low => "Low",
            Priority::Medium => "Medium",
            Priority::High => "High",
        }
    }

    pub fn to_db(self) -> i64 {
        match self {
            Priority::Low => 0,
            Priority::Medium => 1,
            Priority::High => 2,
        }
    }

    pub fn from_db(value: i64) -> Priority {
        match value {
            0 => Priority::Low,
            2 => Priority::High,
            _ => Priority::Medium,
        }
    }
}

#[derive(Clone, Debug)]
pub struct Task {
    pub id: i64,
    pub title: String,
    pub notes: String,
    pub priority: Priority,
    pub status: Status,
    /// ISO date (`YYYY-MM-DD`), empty when there is no due date.
    pub due: String,
}

impl Task {
    pub fn is_done(&self) -> bool {
        self.status == Status::Done
    }

    pub fn due_date(&self) -> Option<NaiveDate> {
        NaiveDate::parse_from_str(&self.due, DATE_FORMAT).ok()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn enums_roundtrip_through_the_database_representation() {
        for s in Status::ALL {
            assert_eq!(Status::from_db(s.to_db()), s);
        }
        for p in Priority::ALL {
            assert_eq!(Priority::from_db(p.to_db()), p);
        }
    }

    #[test]
    fn status_cycles_back_to_the_start() {
        assert_eq!(Status::Todo.next().next().next(), Status::Todo);
    }
}
