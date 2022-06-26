#!/usr/bin/perl
use strict;
use warnings;
use 5.30.0;
no autovivification;
binmode STDOUT, ":utf8";
use utf8;
use Data::Printer;
use JSON;
use Selenium::Chrome;
use HTTP::Cookies;
use HTML::Tree;
use LWP::UserAgent;
use LWP::Simple;
use HTTP::Cookies qw();
use HTTP::Request::Common qw(POST OPTIONS);
use HTTP::Headers;
use Scalar::Util qw(looks_like_number);
use Time::HiRes qw(usleep);
use FindBin;
use lib "$FindBin::Bin/../../lib";
use global;
use time;
use cdc;

my ($chromeProfileNum, $firstId, $lastId) = @ARGV;

# say "";
# say "chromeProfileNum : $chromeProfileNum";
# say "firstId          : $firstId";
# say "lastId           : $lastId";

# Fetching indexed reports.
my %cdcReports           = ();
cdc_reports();
# p%cdcReports;

my $dataDir              = "C:\\Users\\Utilisateur\\AppData\\Local\\Google\\Chrome\\User Data";
my $profileDir           = "Profile $chromeProfileNum";
my $fullPath             = "$dataDir\\$profileDir";

# Using chromeOptions to start chrome.
my $capabilities         = {};
$capabilities->{"goog:chromeOptions"} = {
	"args" => [
		"user-data-dir=$fullPath",
		"profile-directory=$profileDir"
	]
};
my $driver               = Selenium::Chrome->new('extra_capabilities' => $capabilities);
my $baseUrl              = "https://wonder.cdc.gov/vaers.html";

get_reports_data();

$driver->shutdown_binary;

sub cdc_reports {
	my $tb = $dbh->selectall_hashref("SELECT id as cdcReportId, internalId FROM cdc_report WHERE id >= $firstId AND id <= $lastId AND detailsTimestamp IS NULL", 'cdcReportId');
	for my $cdcReportId (sort{$a <=> $b} keys %$tb) {
		my $internalId = %$tb{$cdcReportId}->{'internalId'} // die;
		$cdcReports{$internalId}->{'cdcReportId'} = $cdcReportId;
	}
}

sub get_reports_data {
	$driver->get($baseUrl);
	cdc::verify_disclaimer($driver);
	cdc::select_event_details($driver);
	for my $cdcReportInternalId (sort keys %cdcReports) {
		# next unless $cdcReportInternalId eq '0059272-1';
		my $cdcReportId = $cdcReports{$cdcReportInternalId}->{'cdcReportId'} // die;
		# say "cdcReportId         : $cdcReportId";
		# say "cdcReportInternalId : $cdcReportInternalId";

		# Autocompletting loggin data.
		my $vaersSearchElem = $driver->find_element("(//input[\@name='vaers_report_id'])[1]");
		cdc::simulate_typing($driver, $vaersSearchElem, $cdcReportInternalId);

		# Casting form & verifying number of results.
		cdc::cast_event_form($driver);
		sleep 2;
		my $content = $driver->get_page_source;
		my $tree    = HTML::Tree->new();
		$tree->parse($content);

		# Parsing templates.
		my %reportData = ();
		if ($tree->look_down(class=>"v1")) {
			%reportData = cdc::parse_template_v1($tree);
		} elsif ($tree->look_down(class=>"v2")) {
			die "to code";
		} else {
			open my $out, '>', 'cdc.html';
			print $out $tree->as_HTML('<>&', "\t");
			close $out;
			die "unexpected";
		}

		# Updating data.
		my $reportData = encode_json\%reportData;
		my $sth = $dbh->prepare("UPDATE cdc_report SET reportData = ?, detailsTimestamp = UNIX_TIMESTAMP() WHERE id = $cdcReportId");
		$sth->execute($reportData) or die $sth->err();

		# Returns to form.
		cdc::select_search_form($driver);
		# $driver->shutdown_binary;
		# exit;
	}
}