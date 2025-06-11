const std = @import("std");

pub const monthsStrings: []const []const u8 = &.{
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
};

pub var years_string: [100][]const u8 = undefined;
pub var years_buffers: [100][20]u8 = undefined; // Using [20]u8 as requested

pub fn initYearsString() void {
    for (0..years_string.len) |i| {
        years_string[i] = std.fmt.bufPrint(&years_buffers[i], "{d}", .{2025 - i}) catch unreachable;
    }
}

const DateTime = @This();
year: i32,
month: u8,
day: u8,
hour: u8 = 0,
minute: u8 = 0,
second: u8 = 0,

/// Creates a DateTime instance with the given values
pub fn init(year: i32, month: u8, day: u8, hour: u8, minute: u8, second: u8) DateTime {
    return .{
        .year = year,
        .month = month,
        .day = day,
        .hour = hour,
        .minute = minute,
        .second = second,
    };
}

/// Creates a DateTime instance from a Unix timestamp
pub fn fromTimestamp(timestamp: i64) DateTime {
    const epoch_seconds = std.time.epoch.EpochSeconds{
        .secs = @as(u64, @intCast(@as(u64, @bitCast(timestamp)))),
    };
    const epoch_day = epoch_seconds.getEpochDay();
    const day_seconds = epoch_seconds.getDaySeconds();

    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    return .{
        .year = @as(i32, @intCast(year_day.year)),
        .month = month_day.month.numeric(),
        .day = month_day.day_index + 1,
        .hour = day_seconds.getHoursIntoDay(),
        .minute = day_seconds.getMinutesIntoHour(),
        .second = day_seconds.getSecondsIntoMinute(),
    };
}

/// Gets the current date and time
pub fn now() DateTime {
    const timestamp = std.time.timestamp();
    return DateTime.fromTimestamp(timestamp);
}

/// Gets the month in string format
pub fn monthString(month_index: usize) []const u8 {
    return monthsStrings[month_index - 1];
}

/// Gets the month in string format
pub fn monthFromString(selected_month: []const u8) usize {
    for (monthsStrings, 1..) |month, i| {
        if (std.mem.eql(u8, selected_month, month)) {
            return i;
        }
    }
    return 0;
}

/// Converts this DateTime to a Unix timestamp
pub fn toTimestamp(self: DateTime) i64 {
    var result: i64 = 0;

    // Calculate days from 1970-01-01 to the beginning of the year
    var year: i32 = 1970;
    while (year < self.year) : (year += 1) {
        result += 365 * 86400;
        if (isLeapYear(year)) result += 86400;
    }

    // Add days for each month
    const days_in_month = [_]u16{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    var month: u8 = 1;
    while (month < self.month) : (month += 1) {
        result += @as(i64, days_in_month[month - 1]) * 86400;
        if (month == 2 and isLeapYear(self.year)) result += 86400;
    }

    // Add days, hours, minutes, seconds
    result += @as(i64, self.day - 1) * 86400;
    result += @as(i64, self.hour) * 3600;
    result += @as(i64, self.minute) * 60;
    result += @as(i64, self.second);

    return result;
}

/// Format the date as a string (YYYY-MM-DD HH:MM:SS)
pub fn format(self: DateTime, allocator: std.mem.Allocator) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{d}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{
        self.year, self.month,  self.day,
        self.hour, self.minute, self.second,
    });
}

/// Returns a string representation of just the date (YYYY-MM-DD)
pub fn formatDate(self: DateTime, allocator: std.mem.Allocator) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{
        self.year, self.month, self.day,
    });
}

/// Returns a string representation of just the time (HH:MM:SS)
pub fn formatTime(self: DateTime, allocator: std.mem.Allocator) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{d:0>2}:{d:0>2}:{d:0>2}", .{
        self.hour, self.minute, self.second,
    });
}

/// Add days to this date
pub fn addDays(self: DateTime, days: i32) DateTime {
    const timestamp = self.toTimestamp() + (@as(i64, days) * 86400);
    return DateTime.fromTimestamp(timestamp);
}

/// Add months to this date
pub fn setMonth(self: DateTime, month: usize) DateTime {
    const year = self.year;

    // Adjust day if necessary (e.g., January 31 + 1 month should be February 28/29)
    const days_in_month = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    var max_days = days_in_month[month - 1];
    if (month == 2 and isLeapYear(year)) max_days = 29;

    const day = @min(self.day, max_days);

    return .{
        .year = year,
        .month = @intCast(month),
        .day = day,
        .hour = self.hour,
        .minute = self.minute,
        .second = self.second,
    };
}

/// Add months to this date
pub fn addMonths(self: DateTime, months: i32) DateTime {
    var year = self.year;
    var month = @as(i32, self.month) + months;

    while (month > 12) {
        month -= 12;
        year += 1;
    }

    while (month < 1) {
        month += 12;
        year -= 1;
    }

    // Adjust day if necessary (e.g., January 31 + 1 month should be February 28/29)
    const days_in_month = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    var max_days = days_in_month[@intCast(month - 1)];
    if (month == 2 and isLeapYear(year)) max_days = 29;

    const day = @min(self.day, max_days);

    return .{
        .year = year,
        .month = @intCast(month),
        .day = day,
        .hour = self.hour,
        .minute = self.minute,
        .second = self.second,
    };
}

/// Add years to this date
pub fn setYear(self: DateTime, year: i32) DateTime {
    return .{
        .year = year,
        .month = self.month,
        .day = self.day,
        .hour = self.hour,
        .minute = self.minute,
        .second = self.second,
    };
}

/// Add years to this date
pub fn addYears(self: DateTime, years: i32) DateTime {
    return .{
        .year = self.year + years,
        .month = self.month,
        .day = self.day,
        .hour = self.hour,
        .minute = self.minute,
        .second = self.second,
    };
}

/// Returns true if this date is before the other date
pub fn isBefore(self: DateTime, other: DateTime) bool {
    return self.toTimestamp() < other.toTimestamp();
}

/// Returns true if this date is after the other date
pub fn isAfter(self: DateTime, other: DateTime) bool {
    return self.toTimestamp() > other.toTimestamp();
}

/// Returns true if this date is equal to the other date
pub fn isEqual(self: DateTime, other: DateTime) bool {
    return self.toTimestamp() == other.toTimestamp();
}

/// Returns the day of week (0 = Sunday, 1 = Monday, ..., 6 = Saturday)
pub fn dayOfWeek(self: DateTime) u3 {
    // Using Zeller's congruence algorithm
    const m = if (self.month < 3) self.month + 12 else self.month;
    const y = if (self.month < 3) self.year - 1 else self.year;

    const h = @mod(self.day + @as(u32, @intCast(13 * (m + 1) / 5)) + @as(u32, @intCast(y)) + @as(u32, @intCast(@divTrunc(y, 4))) -
        @as(u32, @intCast(@divTrunc(y, 100))) + @as(u32, @intCast(@divTrunc(y, 400))), 7);

    // Convert to Sunday = 0, Monday = 1, etc.
    return @as(u3, @intCast(@mod(h + 6, 7)));
}

/// Returns whether the given year is a leap year
fn isLeapYear(year: i32) bool {
    // return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
    return (@rem(year, 4) == 0 and @rem(year, 100) != 0) or @rem(year, 400) == 0;
}

/// Returns the number of days in a given month for a specific year
pub fn getDaysInMonth(month: u8, year: i32) u8 {
    const days_in_month = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };

    if (month < 1 or month > 12) {
        return 0; // Invalid month
    }

    if (month == 2 and isLeapYear(year)) {
        return 29;
    }

    return days_in_month[month - 1];
}

/// Returns an array of DateTime objects for each day in the given month and year
pub fn getDaysInMonthArray(allocator: *std.mem.Allocator, month: u8, year: i32) ![]DateTime {
    const days_count = getDaysInMonth(month, year);
    if (days_count == 0) {
        return error.InvalidMonth;
    }

    var result = try allocator.alloc(DateTime, days_count);

    for (0..days_count) |i| {
        result[i] = DateTime.init(year, month, @intCast(i + 1), 0, 0, 0);
    }

    return result;
}

/// Returns a calendar view as an array of DateTime objects for the given month and year
/// This includes days from previous and next months to create a full 5-week (35 day) view
/// Starting from Monday of the week containing the 1st day of the month
/// and ending with Sunday of the week containing the last day of the month
pub fn getCalendarView(allocator: *std.mem.Allocator, month: u8, year: i32) ![]DateTime {
    if (month < 1 or month > 12) return error.InvalidMonth;

    // Create a DateTime for the first day of the month
    const first_day = DateTime.init(year, month, 1, 0, 0, 0);

    // Calculate the day of week for the first day (0 = Sunday, 1 = Monday, ..., 6 = Saturday)
    const first_day_of_week = first_day.dayOfWeek();

    // Calculate how many days we need to include from the previous month
    // If first day is Sunday (0), we need to go back 6 days to start from Monday
    // If first day is Monday (1), we need to go back 0 days
    // If first day is Tuesday (2), we need to go back 1 day, etc.
    const days_from_prev_month: u8 = if (first_day_of_week == 0) 6 else first_day_of_week - 1;

    // Calculate the number of days in the current month
    const days_in_current_month = getDaysInMonth(month, year);

    // Calculate previous month and year
    const prev_month = if (month == 1) 12 else month - 1;
    const prev_year = if (month == 1) year - 1 else year;

    // Calculate next month and year
    const next_month = if (month == 12) 1 else month + 1;
    const next_year = if (month == 12) year + 1 else year;

    // Calculate days from the next month needed to complete 5 weeks (35 days)
    const total_days_needed: u8 = 35;
    const days_from_current_month: u8 = days_in_current_month;
    const days_from_next_month: u8 = total_days_needed - days_from_prev_month - days_from_current_month;

    // Allocate the result array for all 35 days
    var result = try allocator.alloc(DateTime, total_days_needed);

    // Fill in days from the previous month
    const days_in_prev_month = getDaysInMonth(prev_month, prev_year);
    var index: usize = 0;

    for (0..days_from_prev_month) |i| {
        const day = days_in_prev_month - days_from_prev_month + i + 1;
        result[index] = DateTime.init(prev_year, prev_month, @intCast(day), 0, 0, 0);
        index += 1;
    }

    // Fill in days from the current month
    for (0..days_from_current_month) |i| {
        result[index] = DateTime.init(year, month, @intCast(i + 1), 0, 0, 0);
        index += 1;
    }

    // Fill in days from the next month
    for (0..days_from_next_month) |i| {
        result[index] = DateTime.init(next_year, next_month, @intCast(i + 1), 0, 0, 0);
        index += 1;
    }

    return result;
}
