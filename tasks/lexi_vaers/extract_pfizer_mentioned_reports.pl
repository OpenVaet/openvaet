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

my $json;
open my $in, '<', 'data/vaers_reports.json';
while (<$in>) {
    $json .= $_;
}
close $in;
$json = decode_json($json);
my @reports = @$json;

my @problematic_reports = ();

my $problematic_reports = 0;
for my $report_data (@reports) {
    my $narrative = %$report_data{'narrative'} // die;
    $narrative = lc $narrative;
    my @products_listed = @{%$report_data{'products_listed'}};
    if ($narrative =~ /pfizer/) {
        my $has_pfizer_manu = 0;
        for my $product_data (@products_listed) {
            my $manufacturer_name = %$product_data{'manufacturer_name'} // die;
            $manufacturer_name = lc $manufacturer_name;
            if ($manufacturer_name =~ /pfizer/) {
                $has_pfizer_manu = 1;
            }
        }
        if (!$has_pfizer_manu) {
            my $died = %$report_data{'died'} // die;
            if ($died) {
                $problematic_reports++;
                push @problematic_reports, \%$report_data;
                p$report_data;
            }
        }
    }
}

open my $out, '>', "data/problematic_vaers_reports.json";
print $out encode_json\@problematic_reports;
close $out;
say "extracted $problematic_reports problematic reports.";