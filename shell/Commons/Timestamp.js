.pragma library
.import "Duration.js" as Duration

// The one wording of a past moment a surface shows, in local time. A time
// under an hour before NOW reads relative, so a recent check reads as its
// age, as does one less than a minute ahead of NOW; any other, older or
// further ahead, reads as the bar clock does, with the year only when it is
// not NOW's.

var DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
var RELATIVE_MS = 3600 * 1000;
// Time.now ticks once a minute, so a moment inside the current minute can
// lie up to a minute ahead of the NOW a caller reads from it.
var CLOCK_LAG_MS = 60 * 1000;

function twoDigits(n) {
    return (n < 10 ? "0" : "") + n;
}

// MS and NOW are epoch milliseconds: "just now", "12m ago",
// "Fri 9 Oct, 00:19" or "Thu 9 Oct 2025, 00:19".
function text(ms, now) {
    var age = now - ms;
    if (age < 0 && age > -CLOCK_LAG_MS) return "just now";
    if (age >= 0 && age < RELATIVE_MS) {
        var seconds = Math.floor(age / 1000);
        return seconds < 60 ? "just now" : Duration.format(seconds, 1) + " ago";
    }
    var at = new Date(ms);
    var year = at.getFullYear() === new Date(now).getFullYear() ? "" : " " + at.getFullYear();
    return DAYS[at.getDay()] + " " + at.getDate() + " " + MONTHS[at.getMonth()] + year + ", " + twoDigits(at.getHours()) + ":" + twoDigits(at.getMinutes());
}
