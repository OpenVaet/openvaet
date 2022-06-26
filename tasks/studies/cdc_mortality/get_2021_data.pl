#!/usr/bin/perl
use strict;
use warnings;
use 5.30.0;
no autovivification;
binmode STDOUT, ":utf8";
use utf8;
use Data::Printer;
use Data::Dumper;
use JSON;
use Selenium::Chrome;
use File::Temp;
use HTTP::Cookies;
use HTML::Tree;
use LWP::UserAgent;
use LWP::Simple;
use HTTP::Cookies qw();
use HTTP::Request::Common qw(POST OPTIONS);
use HTTP::Headers;
use Hash::Merge;
use Scalar::Util qw(looks_like_number);
use FindBin;
use lib "$FindBin::Bin/../../../lib";

# Project's libraries.
use global;
use time;

my $statsFile       = 'tasks/studies/cdc_mortality/current_2021_data.json';
my $dataDir         = "C:\\Users\\Utilisateur\\AppData\\Local\\Google\\Chrome\\User Data";
my $profileDir      = "Profile 1";
my $fullPath        = "$dataDir\\$profileDir";
my $capabilities    = {};
$capabilities->{"goog:chromeOptions"} = {
	"args" => [
		"user-data-dir=$fullPath",
		"profile-directory=$profileDir"
	]
};
my $driver          = Selenium::Chrome->new('extra_capabilities' => $capabilities);
my $url             = "https://www.cdc.gov/mmwr/volumes/71/wr/mm7117e1.htm";
my $currentDatetime = time::current_datetime();
say "$currentDatetime - Getting [$url]";
$driver->get($url);
sleep 2;
my $content      = $driver->get_page_source;
my $tree         = HTML::Tree->new();
$tree->parse($content);
my $table        = $tree->look_down(class=>"table table-bordered table-responsive");
$table           = $table->find('tbody');
my @trs          = $table->find('tr');
my $currentGroup = 'Total';
my %stats        = ();
# open my $out, '>:utf8', 'tmp.html';
# say $out $tree->as_HTML('<>&', "\t");
for my $tr (@trs) {
	my @tds      = $tr->find('td');
	unless (scalar @tds == 5) {
		die unless scalar @tds == 1;
		$currentGroup = $tds[0]->as_trimmed_text;
	} else {
		my $label                = $tds[0]->as_trimmed_text;
		$label                   = format_value($label);
		$label                   =~ s/≥/>=/;
		my $totalDeaths2020      = $tds[1]->as_trimmed_text;
		my $totalDeathsCovid2020 = $tds[2]->as_trimmed_text;
		my $totalDeaths2021      = $tds[3]->as_trimmed_text;
		my $totalDeathsCovid2021 = $tds[4]->as_trimmed_text;

		# 2020.
		# Formatting total deaths.
		($totalDeaths2020, my $totalDeathsPer100000In2020) = $totalDeaths2020 =~ /(.*) \((.*)\)/;
		$totalDeaths2020            =~ s/\)//;
		$totalDeaths2020            =~ s/,//g  if $totalDeathsCovid2020;
		$totalDeathsPer100000In2020 =~ s/\)//;
		$totalDeathsPer100000In2020 = format_value($totalDeathsPer100000In2020);
		$totalDeathsPer100000In2020 =~ s/,//g  if $totalDeathsPer100000In2020;
		$totalDeathsPer100000In2020 = undef if $totalDeathsPer100000In2020 eq '—';

		# Formatting total COVID deaths.
		($totalDeathsCovid2020, my $totalDeathsCovidPer100000In2020) = $totalDeathsCovid2020 =~ /(.*) \((.*)\)/;
		$totalDeathsCovid2020            =~ s/\)//;
		$totalDeathsCovid2020            =~ s/,//g  if $totalDeathsCovid2020;
		$totalDeathsCovidPer100000In2020 =~ s/\)//;
		$totalDeathsCovidPer100000In2020 = format_value($totalDeathsCovidPer100000In2020);
		$totalDeathsCovidPer100000In2020 =~ s/,//g  if $totalDeathsCovidPer100000In2020;
		$totalDeathsCovidPer100000In2020 = undef if $totalDeathsCovidPer100000In2020 eq '—';

		# 2021.
		# Formatting total deaths.
		($totalDeaths2021, my $totalDeathsPer100000In2021) = $totalDeaths2021 =~ /(.*) \((.*)\)/;
		$totalDeaths2021            =~ s/\)//;
		$totalDeaths2021            =~ s/,//g  if $totalDeathsCovid2020;
		$totalDeathsPer100000In2021 =~ s/\)//;
		$totalDeathsPer100000In2021 = format_value($totalDeathsPer100000In2021);
		$totalDeathsPer100000In2021 =~ s/,//g  if $totalDeathsPer100000In2021;
		$totalDeathsPer100000In2021 = undef if $totalDeathsPer100000In2021 eq '—';

		# Formatting total COVID deaths.
		($totalDeathsCovid2021, my $totalDeathsCovidPer100000In2021) = $totalDeathsCovid2021 =~ /(.*) \((.*)\)/;
		$totalDeathsCovid2021            =~ s/\)//;
		$totalDeathsCovid2021            =~ s/,//g  if $totalDeathsCovid2020;
		$totalDeathsCovidPer100000In2021 =~ s/\)//;
		$totalDeathsCovidPer100000In2021 = format_value($totalDeathsCovidPer100000In2021);
		$totalDeathsCovidPer100000In2021 =~ s/,//g  if $totalDeathsCovidPer100000In2021;
		$totalDeathsCovidPer100000In2021 = undef if $totalDeathsCovidPer100000In2021 eq '—';
		# say $out "$currentGroup | $label | $totalDeaths2020 | $totalDeathsPer100000In2020 | $totalDeathsCovid2020 | $totalDeathsCovidPer100000In2020 | $totalDeaths2021 | $totalDeathsCovidPer100000In2021 | $totalDeathsCovid2021 | $totalDeathsCovidPer100000In2021";
		$stats{'provisional'}->{'2020'}->{'pageData'}->{$currentGroup}->{$label}->{'totalDeaths'}               = $totalDeaths2020;
		$stats{'provisional'}->{'2020'}->{'pageData'}->{$currentGroup}->{$label}->{'totalDeathsPer100000'}      = $totalDeathsPer100000In2020;
		$stats{'provisional'}->{'2020'}->{'pageData'}->{$currentGroup}->{$label}->{'totalDeathsCovid'}          = $totalDeathsCovid2020;
		$stats{'provisional'}->{'2020'}->{'pageData'}->{$currentGroup}->{$label}->{'totalDeathsCovidPer100000'} = $totalDeathsCovidPer100000In2020;
		$stats{'provisional'}->{'2021'}->{'pageData'}->{$currentGroup}->{$label}->{'totalDeaths'}               = $totalDeaths2021;
		$stats{'provisional'}->{'2021'}->{'pageData'}->{$currentGroup}->{$label}->{'totalDeathsPer100000'}      = $totalDeathsPer100000In2021;
		$stats{'provisional'}->{'2021'}->{'pageData'}->{$currentGroup}->{$label}->{'totalDeathsCovid'}          = $totalDeathsCovid2021;
		$stats{'provisional'}->{'2021'}->{'pageData'}->{$currentGroup}->{$label}->{'totalDeathsCovidPer100000'} = $totalDeathsCovidPer100000In2021;
	}
}
# close $out;

sub format_value {
	my $val = shift;
	$val =~ s/–/-/;
	return $val;
}
# say $out $tree->as_HTML('<>&', "\t");

open my $out, '>:utf8', $statsFile or die $!;
say $out encode_json\%stats;
close $out;
# p%stats;