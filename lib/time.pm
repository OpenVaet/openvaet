#!/usr/bin/perl

package time;

use strict;
use warnings;
use v5.14;
no autovivification;
use Time::Local;
use POSIX qw(strftime);
use DateTime;
use DateTime::Format::MySQL;
use Date::Calc qw(Day_of_Week);

sub timestamp_to_datetime
{
    my ($startTimestamp) = @_;
    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($startTimestamp);
    $year += 1900;
    $mon  += 1;
    $mday = "0$mday" if $mday < 10;
    $mon = "0$mon" if $mon < 10;
    $hour = "0$hour" if $hour < 10;
    $min = "0$min" if $min < 10;
    $sec = "0$sec" if $sec < 10 && $sec !~ /../;
    my $startDatetime = "$year-$mon-$mday $hour:$min:$sec";
    return $startDatetime;
}

sub datetime_to_timestamp
{
    my ($datetime) = @_;
    my ($year, $mon, $mday, $hour, $min, $sec) = $datetime =~ /(....)-(..)-(..) (..):(..):(..)/;
    die "wut : [$datetime]" unless $sec;
    my $timestamp  = timelocal($sec, $min, $hour, $mday, $mon-1, $year);
    return $timestamp;
}

sub current_timestamp
{
    my $currentDatetime  = DateTime->now(time_zone => 'Europe/Paris');
    $currentDatetime     = DateTime::Format::MySQL->format_datetime($currentDatetime);
    my $currentTimestamp = datetime_to_timestamp($currentDatetime);
    return $currentTimestamp;
}

sub current_datetime
{
    my $currentDatetime = DateTime->now(time_zone => 'Europe/Paris');
    $currentDatetime    = DateTime::Format::MySQL->format_datetime($currentDatetime);
    return $currentDatetime;
}

sub local_from_utc {
    my ($datetime) = @_;
    my $dt;
    my ($year, $month, $day, $hour, $minute, $seconde) = $datetime =~ /(....)-(..)-(..) (..):(..):(..)/;
    # say "before : $year-$month-$day $hour:$minute:$seconde";
    eval {
        $dt = DateTime->new(
            time_zone => "UTC",
            year      => $year,
            month     => $month,
            day       => $day,
            hour      => $hour,
            minute    => $minute,
            second    => $seconde
        );
    };
    if ($@) {
        die "shouldn't happen";
    }
    $dt->set_time_zone('Europe/Paris');
    my $date = $dt->ymd;   # Retrieves date as a string in 'yyyy-mm-dd' format
    my $time = $dt->hms;   # Retrieves time as a string in 'hh:mm:ss' format
    # say "after : $date $time";
    return "$date $time";
}

sub server_datetime_to_admin_datetime {
    my ($self, $currentDatetime) = @_;
    ($currentDatetime)    = current_datetime() unless $currentDatetime;
    my $adminDatetime     = DateTime::Format::MySQL->parse_datetime($currentDatetime);
    my $adminName         = $self->session('name') || die;
    my $adminTb           = $self->dbh->selectrow_hashref("SELECT admin.id as adminId, admin.timezoneId, timezone.dateTimeName, timezone.timezoneRegionId, timezone_region.name as timeZoneRegionName FROM admin LEFT JOIN timezone ON timezone.id = admin.timezoneId LEFT JOIN timezone_region ON timezone_region.id = timezone.timezoneRegionId WHERE admin.name = ?", undef, $adminName);
    my $adminId           = %$adminTb{'adminId'}   || die;
    my $adminTimeZone;
    if (%$adminTb{'timeZoneRegionName'} && %$adminTb{'dateTimeName'})
    {
        $adminTimeZone    = %$adminTb{'timeZoneRegionName'} . '/' . %$adminTb{'dateTimeName'};
    } else
    {
        $adminTimeZone    = 'Europe/Paris';
    }
    # say "adminTimeZone : $adminTimeZone";
    $adminDatetime->set_time_zone('Europe/Paris'); ## set timezone of server
    $adminDatetime->set_time_zone($adminTimeZone); ## set timezone of server
    $adminDatetime =~ s/T/ /;
    return ($adminDatetime, $adminTimeZone);
}

sub subtract_seconds_to_datetime
{
    my ($datetime, $seconds) = @_;
    my $dt;
    my ($year, $month, $day, $hour, $minute, $seconde) = $datetime =~ /(....)-(..)-(..) (..):(..):(..)/;
    eval {
        $dt = DateTime->new(
            time_zone => "Europe/Paris",
            year      => $year,
            month     => $month,
            day       => $day,
            hour      => $hour,
            minute    => $minute,
            second    => $seconde
        );
    };
    if ($@) {
        $hour--;
        $dt = DateTime->new(
            time_zone => "Europe/Paris",
            year      => $year,
            month     => $month,
            day       => $day,
            hour      => $hour,
            minute    => $minute,
            second    => $seconde
        );
    }
    my $subtractDatetime = $dt->subtract(seconds => $seconds);
    $subtractDatetime    = DateTime::Format::MySQL->format_datetime($subtractDatetime);
    return $subtractDatetime;
}

sub add_seconds_to_datetime
{
    my ($datetime, $seconds) = @_;
    my $dt;
    my ($year, $month, $day, $hour, $minute, $seconde) = $datetime =~ /(....)-(..)-(..) (..):(..):(..)/;
    eval {
        $dt = DateTime->new(
            time_zone => "Europe/Paris",
            year      => $year,
            month     => $month,
            day       => $day,
            hour      => $hour,
            minute    => $minute,
            second    => $seconde
        );
    };
    if ($@) {
        $hour--;
        $dt = DateTime->new(
            time_zone => "Europe/Paris",
            year      => $year,
            month     => $month,
            day       => $day,
            hour      => $hour,
            minute    => $minute,
            second    => $seconde
        );
    }
    my $subtractDatetime = $dt->add(seconds => $seconds);
    $subtractDatetime    = DateTime::Format::MySQL->format_datetime($subtractDatetime);
    return $subtractDatetime;
}

sub insert_server_date
{
    my ($dbh, $serverDate) = @_;
    my ($year, $month, $day) = split '-', $serverDate;
    my ($fromTimestamp, $toTimestamp) = timestamps_from_date($serverDate);
    my $dayOfWeek = date_to_day_of_week($year, $month, $day);
    my $sth = $dbh->prepare("INSERT INTO server_date (date, fromTimestamp, toTimestamp, year, month, day, dayOfWeek) VALUES (?, ?, ?, ?, ?, ?, ?)");
    $sth->execute($serverDate, $fromTimestamp, $toTimestamp, $year, $month, $day, $dayOfWeek) or die $!;
    my $tb = $dbh->selectrow_hashref("SELECT id as serverDateId FROM server_date WHERE date = ?", undef, $serverDate);
    die unless $tb;
    return %$tb{'serverDateId'};
}

sub week_number_from_date {
    my ($date) = @_;
    my ($year, $month, $day) = split '-', $date;
    my $epoch = timelocal( 0, 0, 0, $day, $month - 1, $year - 1900 );
    my $weekNumber  = strftime( "%U", localtime( $epoch ) );
    return $weekNumber;
}

sub timestamps_from_date
{
    my ($date) = @_;
    my $dateFrom = "$date 00:00:00";
    my $dateTo   = "$date 23:59:59";
    my $timestampFrom = datetime_to_timestamp($dateFrom);
    my $timestampTo   = datetime_to_timestamp($dateTo);
    return ($timestampFrom, $timestampTo);
}

sub date_to_day_of_week
{
    my ($year, $month, $day) = @_;
    return Day_of_Week($year,$month,$day);
}

sub calculate_minutes_difference
{
    my ($date1, $date2) = @_;
    # say "[$date1, $date2]";
    my ($dt1, $dt2);
    my ($year1, $month1, $day1, $hour1, $minute1, $seconde1) = $date1 =~ /(....)-(..)-(..) (..):(..):(..)/;
    my ($year2, $month2, $day2, $hour2, $minute2, $seconde2) = $date2    =~ /(....)-(..)-(..) (..):(..):(..)/;
    eval {
        $dt1 = DateTime->new(
            time_zone => "Europe/Paris",
            year      => $year1,
            month     => $month1,
            day       => $day1,
            hour      => $hour1,
            minute    => $minute1
        );
    };
    if ($@) {
        $hour1--;
        $dt1 = DateTime->new(
            time_zone => "Europe/Paris",
            year      => $year1,
            month     => $month1,
            day       => $day1,
            hour      => $hour1,
            minute    => $minute1
        );
    }
    eval {
        $dt2 = DateTime->new(
            time_zone => "Europe/Paris",
            year      => $year2,
            month     => $month2,
            day       => $day2,
            hour      => $hour2,
            minute    => $minute2
        );
    };
    if ($@) {
        $hour2--;
        $dt2 = DateTime->new(
            time_zone => "Europe/Paris",
            year      => $year2,
            month     => $month2,
            day       => $day2,
            hour      => $hour2,
            minute    => $minute2
        );
    }
    my $seconds = $dt2->subtract_datetime_absolute($dt1)->delta_seconds;
    # say "seconds   : $seconds";
    my $minutes = int(($seconds / 60 * 1000) / 1000);
    # say "minutes   : $minutes";
    return ($minutes);
}



1;