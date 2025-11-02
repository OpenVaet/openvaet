#!/usr/bin/perl
use strict;
use warnings;
use 5.26.0;
no autovivification;
binmode STDOUT, ":utf8";
use utf8;
use Data::Printer;
use Data::Dumper;
use File::Path qw(make_path);
use Text::CSV qw( csv );
use Math::Round qw(nearest);
use Date::DayOfWeek;
use Date::WeekNumber qw/ iso_week_number /;
use Encode;
use Encode::Unicode;
use JSON;
use FindBin;
use Scalar::Util qw(looks_like_number);
use File::stat;
use lib "$FindBin::Bin/../../lib";

# Project's libraries.
use time;

my %statuses = ();

load_statuses();

sub load_statuses {
    my $json;
    open my $in, '<', 'data/vaers_reports_statuses.json';
    while (<$in>) {
        $json .= $_;
    }
    close $in;
    $json = decode_json($json);
    %statuses = %{%$json{'statuses'}};
}

my $json;
open my $in, '<', 'data/problematic_vaers_reports.json';
while (<$in>) {
    $json .= $_;
}
close $in;
$json = decode_json($json);

my @related = ();
my @reports = @$json;
for my $report_data (@reports) {
    my $vaers_id = %$report_data{'vaers_id'} // die;
    my $narrative = %$report_data{'narrative'} // die;
    $narrative = lc $narrative;
    my $status = $statuses{$vaers_id}->{'status'} // die;
    next unless $status eq 'related';
    push @related, \%$report_data;
}

open my $out, '>', "data/related_vaers_reports.json";
print $out encode_json\@related;
close $out;
say "extracted related reports.";