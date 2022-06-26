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
use lib "$FindBin::Bin/../../lib";

# Project's libraries.
use global;
use time;

my $covidOnly               = 'false'; # Either true or false (will focus only on COVID vaccines if true).
my $isIndexedOnly           = 'true';  # Either true or false (will focus only on drugs defined to be indexed).

my %ecdcSeriousness         = ();
$ecdcSeriousness{'1'}       = 'Serious';
$ecdcSeriousness{'2'}       = 'Non-Serious';
$ecdcSeriousness{'3'}       = 'Not Available';

my $dataDir                 = "C:\\Users\\Utilisateur\\AppData\\Local\\Google\\Chrome\\User Data";
my $profileDir              = "Profile 1";
my $fullPath                = "$dataDir\\$profileDir";
my $downloadDir             = "C:/Users/Utilisateur/Downloads";
my $lineListingReportPath   = $downloadDir . '/Run Line Listing Report.csv';
if (-f $lineListingReportPath) {
	unlink $lineListingReportPath or die;
	die if -f $lineListingReportPath;
} 
my $noticesPdfDir           = 'raw_data/ecdc/notices';
die unless -d $noticesPdfDir;
my $exportsPdfDir           = 'raw_data/ecdc/exports';
die unless -d $exportsPdfDir;
my $capabilities            = {};
$capabilities->{"goog:chromeOptions"} = {
	"args" => [
		"user-data-dir=$fullPath",
		"profile-directory=$profileDir"
	]
};
my $ecdcSourceId            = 1;
my $driver                  = Selenium::Chrome->new('extra_capabilities' => $capabilities);
my %ecdcDrugs               = ();
my $latestEcdcDrugId        = 0;
ecdc_drugs();
my %ecdcCountries           = ();
my $latestEcdcCountryId     = 0;
ecdc_countries();
my %ecdcAges                = ();
my $latestEcdcAgeId         = 0;
ecdc_ages();
my %ecdcSexs               = ();
my $latestEcdcSexId         = 0;
ecdc_sexes();
my %ecdcCountryTypes        = ();
my $latestEcdcCountryTypeId = 0;
ecdc_country_types();
my %ecdcReporters           = ();
my $latestEcdcReporterId    = 0;
ecdc_reporters();

# Getting list of drugs (A-Z, 0-9) if it hasn't been updated upon the last hour.
my $indexUpdateTimestamp    = ecdc_index_update();
my $currentTimestamp        = time::current_timestamp();
if (!$indexUpdateTimestamp || ($indexUpdateTimestamp + 3600) < $currentTimestamp) {
	get_ecdc_drugs_list();
}

# Stores updates already performed on ECDC's update date.
my %ecdcDrugUpdates         = ();
my $latestEcdcDrugUpdateId  = 0;
my %timestampScanned        = ();

# Getting total adverse cases reported to date.
get_ecdc_adverse_cases_statistics();
my %ecdcYears                       = ();
my %ecdcYearsFromIds                = ();
my $latestEcdcYearId                = 0;
ecdc_years();
my %ecdcDrugYears                   = ();
my $latestEcdcDrugYearId            = 0;
ecdc_drug_years();
my %ecdcDrugYearSeriousnesses       = ();
my $latestEcdcDrugYearSeriousnessId = 0;
ecdc_drug_year_seriousnesses();

# Getting earliest year listed for each notice.
get_ecdc_notices_earliest_year_listed();

my %ecdcNotices                     = ();
my $latestEcdcNoticeId              = 0;
ecdc_notices();
my %ecdcDrugNotices                 = ();
my $latestEcdcDrugNoticeId          = 0;
ecdc_drug_notices();
my %ecdcReactions                   = ();
my $latestEcdcReactionId            = 0;
ecdc_reactions();
my %ecdcReactionOutcomes            = ();
my $latestEcdcReactionOutcomeId     = 0;
ecdc_reaction_outcomes();
my %ecdcReactionSeriousnesses       = ();
my $latestEcdcReactionSeriousnessId = 0;
ecdc_reaction_seriousnesses();
my %ecdcNoticeReactions             = ();
my $latestEcdcNoticeReactionId      = 0;
ecdc_notice_reactions();

# Getting notices updates.
get_ecdc_notices();

$driver->shutdown_binary;

sub ecdc_drugs {
	my $currentDatetime = time::current_datetime();
	say "$currentDatetime - Loading [Known Drugs]" if $latestEcdcDrugId == 0;
	my $tb = $dbh->selectall_hashref("SELECT id as ecdcDrugId, internalId, name, url, changelog, totalCasesScrapped, ecsApproval, updateTimestamp, reportsUpdateTimestamp, aeFromEcdcYearId, hasNullGateYear, earliestAERTimestamp, isIndexed FROM ecdc_drug WHERE id > $latestEcdcDrugId", 'ecdcDrugId');
	for my $ecdcDrugId (sort{$a <=> $b} keys %$tb) {
		$latestEcdcDrugId          = $ecdcDrugId;
		my $ecsApproval            = %$tb{$ecdcDrugId}->{'ecsApproval'}     // die;
    	$ecsApproval               = unpack("N", pack("B32", substr("0" x 32 . $ecsApproval, -32)));
		my $isIndexed              = %$tb{$ecdcDrugId}->{'isIndexed'}       // die;
    	$isIndexed                 = unpack("N", pack("B32", substr("0" x 32 . $isIndexed, -32)));
		my $hasNullGateYear        = %$tb{$ecdcDrugId}->{'hasNullGateYear'} // die;
    	$hasNullGateYear           = unpack("N", pack("B32", substr("0" x 32 . $hasNullGateYear, -32)));
		my $internalId             = %$tb{$ecdcDrugId}->{'internalId'}      // die;
		my $name                   = %$tb{$ecdcDrugId}->{'name'}            // die;
		my $url                    = %$tb{$ecdcDrugId}->{'url'}             // die;
		my $changelog              = %$tb{$ecdcDrugId}->{'changelog'}       // die;
		my $updateTimestamp        = %$tb{$ecdcDrugId}->{'updateTimestamp'};
		my $aeFromEcdcYearId       = %$tb{$ecdcDrugId}->{'aeFromEcdcYearId'};
		my $reportsUpdateTimestamp = %$tb{$ecdcDrugId}->{'reportsUpdateTimestamp'};
		my $earliestAERTimestamp   = %$tb{$ecdcDrugId}->{'earliestAERTimestamp'};
		$ecdcDrugs{$internalId}->{'ecdcDrugId'}             = $ecdcDrugId;
		$ecdcDrugs{$internalId}->{'changelog'}              = $changelog;
		$ecdcDrugs{$internalId}->{'name'}                   = $name;
		$ecdcDrugs{$internalId}->{'url'}                    = $url;
		$ecdcDrugs{$internalId}->{'isIndexed'}              = $isIndexed;
		$ecdcDrugs{$internalId}->{'ecsApproval'}            = $ecsApproval;
		$ecdcDrugs{$internalId}->{'updateTimestamp'}        = $updateTimestamp;
		$ecdcDrugs{$internalId}->{'hasNullGateYear'}        = $hasNullGateYear;
		$ecdcDrugs{$internalId}->{'aeFromEcdcYearId'}       = $aeFromEcdcYearId;
		$ecdcDrugs{$internalId}->{'reportsUpdateTimestamp'} = $reportsUpdateTimestamp;
		$ecdcDrugs{$internalId}->{'earliestAERTimestamp'}   = $earliestAERTimestamp;
	}
}

sub ecdc_countries {
	my $tb = $dbh->selectall_hashref("SELECT id as ecdcCountryId, name FROM ecdc_country WHERE id > $latestEcdcCountryId", 'ecdcCountryId');
	for my $ecdcCountryId (sort{$a <=> $b} keys %$tb) {
		$latestEcdcCountryId = $ecdcCountryId;
		my $name = %$tb{$ecdcCountryId}->{'name'} // die;
		$ecdcCountries{$name}->{'ecdcCountryId'} = $ecdcCountryId;
	}
}

sub ecdc_country_types {
	my $tb = $dbh->selectall_hashref("SELECT id as ecdcCountryTypeId, name FROM ecdc_country_type WHERE id > $latestEcdcCountryTypeId", 'ecdcCountryTypeId');
	for my $ecdcCountryTypeId (sort{$a <=> $b} keys %$tb) {
		$latestEcdcCountryTypeId = $ecdcCountryTypeId;
		my $name = %$tb{$ecdcCountryTypeId}->{'name'} // die;
		$ecdcCountryTypes{$name}->{'ecdcCountryTypeId'} = $ecdcCountryTypeId;
	}
}

sub ecdc_ages {
	my $tb = $dbh->selectall_hashref("SELECT id as ecdcAgeId, name FROM ecdc_age WHERE id > $latestEcdcAgeId", 'ecdcAgeId');
	for my $ecdcAgeId (sort{$a <=> $b} keys %$tb) {
		$latestEcdcAgeId = $ecdcAgeId;
		my $name = %$tb{$ecdcAgeId}->{'name'} // die;
		$ecdcAges{$name}->{'ecdcAgeId'} = $ecdcAgeId;
	}
}

sub ecdc_sexes {
	my $tb = $dbh->selectall_hashref("SELECT id as ecdcSexId, name FROM ecdc_sex WHERE id > $latestEcdcSexId", 'ecdcSexId');
	for my $ecdcSexId (sort{$a <=> $b} keys %$tb) {
		$latestEcdcSexId = $ecdcSexId;
		my $name = %$tb{$ecdcSexId}->{'name'} // die;
		$ecdcSexs{$name}->{'ecdcSexId'} = $ecdcSexId;
	}
}

sub ecdc_reporters {
	my $tb = $dbh->selectall_hashref("SELECT id as ecdcReporterId, name FROM ecdc_reporter WHERE id > $latestEcdcReporterId", 'ecdcReporterId');
	for my $ecdcReporterId (sort{$a <=> $b} keys %$tb) {
		$latestEcdcReporterId = $ecdcReporterId;
		my $name = %$tb{$ecdcReporterId}->{'name'} // die;
		$ecdcReporters{$name}->{'ecdcReporterId'} = $ecdcReporterId;
	}
}

sub ecdc_index_update {
	my $tb = $dbh->selectrow_hashref("SELECT indexUpdateTimestamp FROM source WHERE id = $ecdcSourceId", undef);
	my $indexUpdateTimestamp = %$tb{'indexUpdateTimestamp'};
	return $indexUpdateTimestamp;
}

sub get_ecdc_drugs_list {
	my $baseUrl = "https://www.adrreports.eu/fr/search_subst.html";
	my $currentDatetime = time::current_datetime();
	say "$currentDatetime - Getting [$baseUrl]";
	$driver->get($baseUrl);
	verify_disclaimer();
	browse_a_z_list();
	get_0_9_list();

	# Updates index update timestamp.
	my $sth = $dbh->prepare("UPDATE source SET indexUpdateTimestamp = UNIX_TIMESTAMP() WHERE id = $ecdcSourceId");
	$sth->execute() or die $sth->err();
}

sub verify_disclaimer {
	my $currentDatetime = time::current_datetime();
	say "$currentDatetime - Verifying disclaimer";
	sleep 2;
	my $content = $driver->get_page_source;
	my $tree    = HTML::Tree->new();
	$tree->parse($content);
    if ($tree->look_down("name" => "Submit")) {
		my $acceptDisclaimerButton = $driver->find_element("(//input[\@name='Submit'])[1]");
		$acceptDisclaimerButton->click();
		sleep 2;
    }
}

sub browse_a_z_list {
	for my $letter ('a' .. 'z') {
		my $currentDatetime = time::current_datetime();
		STDOUT->printflush("\r$currentDatetime - Getting drugs list - [$letter]");
		my $url = "https://www.adrreports.eu/tables/substance/$letter.html";
		# say "url : $url";
		$driver->get($url);
		sleep 2;
		my $content = $driver->get_page_source;
		my $tree    = HTML::Tree->new();
		$tree->parse($content);
    	# say $tree->as_HTML('<>&', "\t");

    	my $tbody = $tree->find('tbody');
    	my @trs   = $tbody->find('tr');
    	for my $tr (@trs) {
    		my $url  = $tr->find('a');
    		$url     = $url->attr_get_i('href');
    		my $name = $tr->as_trimmed_text;
    		# say "$name - $url";
    		process_drug($name, $url);
    	}
	}
	say "";
}

sub get_0_9_list {
	my $url = "https://www.adrreports.eu/tables/substance/0-9.html";
	my $currentDatetime = time::current_datetime();
	STDOUT->printflush("\r$currentDatetime - Getting drugs list - [0-9]");
	# say "url : $url";
	$driver->get($url);
	sleep 2;
	my $content = $driver->get_page_source;
	my $tree    = HTML::Tree->new();
	$tree->parse($content);
	# say $tree->as_HTML('<>&', "\t");

	my $tbody = $tree->find('tbody');
	my @trs   = $tbody->find('tr');
	for my $tr (@trs) {
		my $url  = $tr->find('a');
		$url     = $url->attr_get_i('href');
		my $name = $tr->as_trimmed_text;
		# say "$name - $url";
		process_drug($name, $url);
	}
	say "";
}

sub process_drug {
	my ($name, $url) = @_;
	my ($internalId) = $url =~ /P3=1\+(.*)$/;
	die unless $internalId;
	# say "internalId : $internalId";
	# say "name : $name";
	my $ecsApproval = 1;
	if ($name =~ /\*$/) {
		$ecsApproval = 0;
		$name =~ s/\*$//;
		# say "indeed";
		# say "name : $name";
		# c_e();
	}

	# Verifying if the drug needs to be created.
	unless (exists $ecdcDrugs{$internalId}->{'ecdcDrugId'}) {
		my @changelog = ();
		my $creationTimestamp = time::current_timestamp();
		my %obj = ();
		$obj{$creationTimestamp}->{'internalId'}  = $internalId;
		$obj{$creationTimestamp}->{'name'}        = $name;
		$obj{$creationTimestamp}->{'url'}         = $url;
		$obj{$creationTimestamp}->{'ecsApproval'} = $ecsApproval;
		push @changelog, \%obj;
		my $changelog = encode_json\@changelog;
		# p$changelog;
		my $sth = $dbh->prepare("INSERT INTO ecdc_drug (internalId, name, url, ecsApproval, changelog) VALUES (?, ?, ?, $ecsApproval, ?)");
		$sth->execute($internalId, $name, $url, $changelog) or die $sth->err();
		ecdc_drugs();
	} else {

		# Verifying data which may have changed.
		if ($ecdcDrugs{$internalId}->{'name'}        ne $name) {
			p$ecdcDrugs{$internalId};
			say "name : $name";
			die "name change to log";
		}
		if ($ecdcDrugs{$internalId}->{'url'}         ne $url) {
			p$ecdcDrugs{$internalId};
			say "url : $url";
			die "url change to log";
		}
		if ($ecdcDrugs{$internalId}->{'ecsApproval'} ne $ecsApproval) {
			my $ecdcDrugId = $ecdcDrugs{$internalId}->{'ecdcDrugId'} // die;
			my $changelog  = $ecdcDrugs{$internalId}->{'changelog'}  // die;
			$changelog     = decode_json($changelog);
			my @changelog  = @$changelog;
			my $creationTimestamp = time::current_timestamp();
			my %obj        = ();
			$obj{$creationTimestamp}->{'internalId'}  = $internalId;
			$obj{$creationTimestamp}->{'changelog'}   = $changelog;
			$obj{$creationTimestamp}->{'name'}        = $name;
			$obj{$creationTimestamp}->{'url'}         = $url;
			$obj{$creationTimestamp}->{'ecsApproval'} = $ecsApproval;
			push @changelog, \%obj;
			$changelog = encode_json\@changelog;
			my $sth = $dbh->prepare("UPDATE ecdc_drug SET ecsApproval = $ecsApproval, changelog = ? WHERE id = $ecdcDrugId");
			$sth->execute($changelog) or die $sth->err();
			$ecdcDrugs{$internalId}->{'changelog'} = $changelog;
		}
	}
}

sub c_e {
	$driver->shutdown_binary;
	exit;
}

sub ecdc_drug_update {
	my ($timestamp) = @_;
	my $tb = $dbh->selectall_hashref("
		SELECT 
			ecdc_drug_update.id as ecdcDrugUpdateId,
			ecdc_drug_update.ecdcDrugId,
			ecdc_drug_update.total
		FROM ecdc_drug_update
		WHERE ecdc_drug_update.updateTimestamp = $timestamp
	", 'ecdcDrugUpdateId');
	for my $ecdcDrugUpdateId (sort{$a <=> $b} keys %$tb) {
		my $ecdcDrugId = %$tb{$ecdcDrugUpdateId}->{'ecdcDrugId'} // die;
		my $total      = %$tb{$ecdcDrugUpdateId}->{'total'}      // die;
		$ecdcDrugUpdates{$ecdcDrugId}->{'ecdcDrugUpdateId'} = $ecdcDrugUpdateId;
		$ecdcDrugUpdates{$ecdcDrugId}->{'total'}            = $total;
	}
}

sub get_ecdc_adverse_cases_statistics {
	my ($currentCase, $totalCases) = (0, 0);
	for my $internalId (sort{$a <=> $b} keys %ecdcDrugs) {
		my $ecdcDrugId   = $ecdcDrugs{$internalId}->{'ecdcDrugId'} // die;
		next if exists $ecdcDrugUpdates{$ecdcDrugId}->{'ecdcDrugUpdateId'};
		my $ecdcDrugName = $ecdcDrugs{$internalId}->{'name'}   // die;
		if ($covidOnly eq 'true') {
			next if $ecdcDrugName !~ /COVID-19/;
		}
		my $isIndexed    = $ecdcDrugs{$internalId}->{'isIndexed'} // die;
		if ($isIndexedOnly eq 'true') {
			next unless $isIndexed;
		}
		$totalCases++;
	}
	my $displayed = 0;
	for my $internalId (sort{$a <=> $b} keys %ecdcDrugs) {
		my $ecdcDrugId = $ecdcDrugs{$internalId}->{'ecdcDrugId'} // die;
		next if exists $ecdcDrugUpdates{$ecdcDrugId}->{'ecdcDrugUpdateId'};
		my $name   = $ecdcDrugs{$internalId}->{'name'}   // die;
		if ($covidOnly eq 'true') {
			next if $name !~ /COVID-19/;
		}
		my $isIndexed = $ecdcDrugs{$internalId}->{'isIndexed'} // die;
		if ($isIndexedOnly eq 'true') {
			next unless $isIndexed;
		}
		my $url    = $ecdcDrugs{$internalId}->{'url'}    // die;
		# say "\nurl : $url";
		# say "$ecdcDrugId - $internalId - $name - $url";
		$driver->get($url);
		sleep 4;
		my $content = $driver->get_page_source;
		my $tree    = HTML::Tree->new();
		$tree->parse($content);
		# open my $out, '>', 'tree.html';
    	# say $out $tree->as_HTML('<>&', "\t");
		# close $out;
		# sleep 15;

		# Fetching total adverse cases.
		my $data = $tree->look_down(viewname=>"narrativeView!1");
		unless ($data) {
			my $attempts = 0;
			while (!$data) {
				# say "Awaiting for content loading";
				sleep 1;
				$attempts++;
				my $content = $driver->get_page_source;
				my $tree    = HTML::Tree->new();
				$tree->parse($content);
				$data = $tree->look_down(viewname=>"narrativeView!1");
				last if $attempts == 100;
			}
			next unless $data;
		}
		my $totalText = $data->as_trimmed_text;
		die "haven't found expected pattern on [$url]"
			unless $totalText =~ /The number of individual cases identified in EudraVigilance for .* is .* \(up to .*\/.*\/.*\)/;
		my ($total, $day, $month, $year) = $totalText =~ /The number of individual cases identified in EudraVigilance for .* is (.*) \(up to (.*)\/(.*)\/(.*)\)/;
		$total =~ s/\,//g;
		$total =~ s/\D//g;
		die "failed to identify current total on [$url], total : [$total]"
			unless looks_like_number $total;
		# say "totalText : $totalText";
		# say "total     : $total";
		# say "day       : $day";
		# say "month     : $month";
		# say "year      : $year";
		my $datetime  = "$year-$month-$day 12:00:00";
		my $timestamp = time::datetime_to_timestamp($datetime);
		if (!exists $timestampScanned{$timestamp}) {
			$timestampScanned{$timestamp} = 1;
			ecdc_drug_update($timestamp);
			($currentCase, $totalCases) = (0, 0);
			for my $internalId (sort{$a <=> $b} keys %ecdcDrugs) {
				my $ecdcDrugId = $ecdcDrugs{$internalId}->{'ecdcDrugId'} // die;
				my $ecdcDrugName = $ecdcDrugs{$internalId}->{'name'}   // die;
				if ($covidOnly eq 'true') {
					next if $ecdcDrugName !~ /COVID-19/;
				}
				my $isIndexed = $ecdcDrugs{$internalId}->{'isIndexed'} // die;
				if ($isIndexedOnly eq 'true') {
					next unless $isIndexed;
				}
				if (exists $ecdcDrugUpdates{$ecdcDrugId}->{'ecdcDrugUpdateId'}) {
					$currentCase++;
				}
				$totalCases++;
			}
		}
		next if exists $ecdcDrugUpdates{$ecdcDrugId}->{'ecdcDrugUpdateId'};
		my $currentDatetime = time::current_datetime();
		$currentCase++;
		$displayed = 1;
		STDOUT->printflush("\r$currentDatetime - Getting Overview Statistics - [$currentCase / $totalCases]");
		# say "datetime  : $datetime";
		# say "timestamp : $timestamp";
		my %mainData = get_table_details($url, $tree);
		# p%mainData;

		# Clicking EEA by Countries.
		%mainData = get_eea_by_countries(%mainData);

		# Updating stats.
		die unless keys %mainData;
		my $json = encode_json\%mainData;
		
		# p$json;
		my $sth1 = $dbh->prepare("INSERT INTO ecdc_drug_update (updateTimestamp, ecdcDrugId, total, stats) VALUES (?, ?, ?, ?)");
		$sth1->execute($timestamp, $ecdcDrugId, $total, $json) or die $sth1->err();

		# Updates the total cases (and scrapping update timestamp) for the drug.
		my $currentTimestamp = time::current_timestamp();
		my $sth2 = $dbh->prepare("UPDATE ecdc_drug SET totalCasesDisplayed = $total, updateTimestamp = $timestamp, scrappingTimestamp = UNIX_TIMESTAMP(), overviewStats = ? WHERE id = $ecdcDrugId");
		$sth2->execute($json) or die $sth2->err();
		$ecdcDrugs{$internalId}->{'updateTimestamp'} = $timestamp;
	}
	say "" if $displayed;
}

sub get_table_details {
	my ($url, $tree) = @_;

	# Fetching cases by groups.
	my @tableLabels = $tree->look_down(class=>"OOMCA");
	my %tableLabels = ();
	my $labelNum = 0;
	for my $tableLabel (@tableLabels) {
		my $label = $tableLabel->find('td');
		$label = $label->as_trimmed_text;
		next if $label eq 'Cases' || $label eq '%';
		$labelNum++;
		$tableLabels{$labelNum} = $label;
		# say $out $tableLabel->as_HTML('<>&', "\t");
	}
	# p%tableLabels;
	my @tables   = $tree->look_down(class=>"PTChildPivotTable");
	my $tableNum = 0;
	my %tableValues = ();
	for my $table (@tables) {
		$tableNum++;
		my $tableLabel = $tableLabels{$tableNum} // die;
		my @columns = $table->look_down(class=>"mPTHC PTRHC0 OOLT");
		my @values  = $table->look_down(class=>"mPTDC PTDC OORT");
		my $colNum  = 0;
		my %columns = ();
		for my $col (@columns) {
			my $name = $col->as_trimmed_text;
			$colNum++;
			$columns{$colNum} = $name;
		}
		# say "tableLabel : [$tableLabel]";
		# p%columns;
		my $valNum  = 0;
		for my $val (@values) {
			my $value = $val->as_trimmed_text;
			$valNum++;
			$value =~ s/\,//g;
			die "failed to identify current value on [$url]"
				unless looks_like_number $value;
			my $column = $columns{$valNum} // die;
			$tableValues{$tableLabel}->{$column} = $value;
		}
		# say $out $table->as_HTML('<>&', "\t");
	}

	# For each age group, processing stats.
	my %values = ();
	die unless exists $tableValues{'Age Group'};
	for my $ageGroup (sort keys %{$tableValues{'Age Group'}}) {
		my $ageGroupTotal = $tableValues{'Age Group'}->{$ageGroup} // die;
		# say "ageGroup      : $ageGroup";
		# say "ageGroupTotal : $ageGroupTotal";
		unless (exists $ecdcAges{$ageGroup}->{'ecdcAgeId'}) {
			my $sth = $dbh->prepare("INSERT INTO ecdc_age (name) VALUES (?)");
			$sth->execute($ageGroup) or die $sth->err();
			ecdc_ages();
		}
		my $ecdcAgeId = $ecdcAges{$ageGroup}->{'ecdcAgeId'} // die;
		$values{'byAge'}->{$ecdcAgeId} = $ageGroupTotal;
	}

	# For each country type group, processing stats.
	die unless exists $tableValues{'Occurrence Country EEA/Non EEA'};
	for my $countryType (sort keys %{$tableValues{'Occurrence Country EEA/Non EEA'}}) {
		my $countryTypeTotal = $tableValues{'Occurrence Country EEA/Non EEA'}->{$countryType} // die;
		# say "countryType      : $countryType";
		# say "countryTypeTotal : $countryTypeTotal";
		unless (exists $ecdcCountryTypes{$countryType}->{'ecdcCountryTypeId'}) {
			my $sth = $dbh->prepare("INSERT INTO ecdc_country_type (name) VALUES (?)");
			$sth->execute($countryType) or die $sth->err();
			ecdc_country_types();
		}
		my $ecdcCountryTypeId = $ecdcCountryTypes{$countryType}->{'ecdcCountryTypeId'} // die;
		$values{'byCountryType'}->{$ecdcCountryTypeId} = $countryTypeTotal;
	}

	# For each sex group, processing stats.
	die unless exists $tableValues{'Sex'};
	for my $sexGroup (sort keys %{$tableValues{'Sex'}}) {
		my $sexGroupTotal = $tableValues{'Sex'}->{$sexGroup} // die;
		# say "sexGroup      : $sexGroup";
		# say "sexGroupTotal : $sexGroupTotal";
		unless (exists $ecdcSexs{$sexGroup}->{'ecdcSexId'}) {
			my $sth = $dbh->prepare("INSERT INTO ecdc_sex (name) VALUES (?)");
			$sth->execute($sexGroup) or die $sth->err();
			ecdc_sexes();
		}
		my $ecdcSexId = $ecdcSexs{$sexGroup}->{'ecdcSexId'} // die;
		$values{'bySex'}->{$ecdcSexId} = $sexGroupTotal;
	}

	# For each reporter group, processing stats.
	if (exists $tableValues{'Reporter Group'}) {
		for my $reporterGroup (sort keys %{$tableValues{'Reporter Group'}}) {
			my $reporterGroupTotal = $tableValues{'Reporter Group'}->{$reporterGroup} // die;
			# say "reporterGroup      : $reporterGroup";
			# say "reporterGroupTotal : $reporterGroupTotal";
			unless (exists $ecdcReporters{$reporterGroup}->{'ecdcReporterId'}) {
				my $sth = $dbh->prepare("INSERT INTO ecdc_reporter (name) VALUES (?)");
				$sth->execute($reporterGroup) or die $sth->err();
				ecdc_reporters();
			}
			my $ecdcReporterId = $ecdcReporters{$reporterGroup}->{'ecdcReporterId'} // die;
			$values{'byReporter'}->{$ecdcReporterId} = $reporterGroupTotal;
		}
	}
	return %values;
}

sub get_eea_by_countries {
	my (%mainData) = @_;
	# p%mainData;
	my $countriesButton = $driver->find_element("(//div[\@title='Number of Individual Cases by EEA countries'])[1]");
	$countriesButton->click();
	sleep 5;
	# say "Clicking XPATH SVG";
	eval {
		my $xpathSvg = $driver->find_element("//*[name()='svg']//*[local-name()='text' and \@fill='#333399']");
		$xpathSvg->click();
		# say "xpathSvg : ";
		# p$xpathSvg;
	};
	if ($@) {
		return %mainData;
	}
	sleep 1;
	eval {
		my $switchButton = $driver->find_element("(//div[\@id='menuOptionItem_Switchtotable'])[1]");
		$switchButton->click();
	};
	if ($@) {
		return %mainData;
	}
	sleep 5;
	my $content = $driver->get_page_source;
	my $tree    = HTML::Tree->new();
	$tree->parse($content);
	unless ($tree->look_down(class=>"PTChildPivotTable")) {
		return %mainData;
	}
	my $tableData = $tree->look_down(class=>"PTChildPivotTable");
	$tableData = $tableData->find('tbody');
	my @trs = $tableData->find('tr');
	for my $tr (@trs) {
		my @tds = $tr->find('td');
		next unless scalar @tds == 2;
		my $ecdcCountryName      = $tds[0]->as_trimmed_text;
		next if $ecdcCountryName eq 'Total';
		my $ecdcCountryDrugCases = $tds[1]->as_trimmed_text;
		$ecdcCountryDrugCases    =~ s/\,//g;
		unless (exists $ecdcCountries{$ecdcCountryName}->{'ecdcCountryId'}) {
			my $sth = $dbh->prepare("INSERT INTO ecdc_country (name) VALUES (?)");
			$sth->execute($ecdcCountryName) or die $sth->err();
			ecdc_countries();
		}
		my $ecdcCountryId = $ecdcCountries{$ecdcCountryName}->{'ecdcCountryId'} // die;
		$mainData{'byCountry'}->{$ecdcCountryId} = $ecdcCountryDrugCases;
		# say "ecdcCountryId        : $ecdcCountryId";
		# say "ecdcCountryName      : $ecdcCountryName";
		# say "ecdcCountryDrugCases : $ecdcCountryDrugCases";
	}
	return %mainData;
}

sub ecdc_years {
	my $tb = $dbh->selectall_hashref("SELECT id as ecdcYearId, name FROM ecdc_year WHERE id > $latestEcdcYearId", 'ecdcYearId');
	for my $ecdcYearId (sort{$a <=> $b} keys %$tb) {
		$latestEcdcYearId = $ecdcYearId;
		my $name = %$tb{$ecdcYearId}->{'name'} // die;
		$ecdcYears{$name}->{'ecdcYearId'} = $ecdcYearId;
		$ecdcYearsFromIds{$ecdcYearId}->{'name'} = $name;
	}
}

sub ecdc_drug_years {
	my $currentDatetime = time::current_datetime();
	say "$currentDatetime - Loading [Known Drugs / Years Relations]" if $latestEcdcDrugYearId == 0;
	my $tb = $dbh->selectall_hashref("SELECT id as ecdcDrugYearId, ecdcDrugId, ecdcYearId FROM ecdc_drug_year WHERE id > $latestEcdcDrugYearId", 'ecdcDrugYearId');
	for my $ecdcDrugYearId (sort{$a <=> $b} keys %$tb) {
		$latestEcdcDrugYearId = $ecdcDrugYearId;
		my $ecdcDrugId = %$tb{$ecdcDrugYearId}->{'ecdcDrugId'} // die;
		my $ecdcYearId = %$tb{$ecdcDrugYearId}->{'ecdcYearId'} // die;
		$ecdcDrugYears{$ecdcDrugId}->{$ecdcYearId}->{'ecdcDrugYearId'} = $ecdcDrugYearId;
	}
}

sub ecdc_drug_year_seriousnesses {
	my $currentDatetime = time::current_datetime();
	say "$currentDatetime - Loading [Known Drugs / Years / Seriousnesses Relations]" if $latestEcdcDrugYearSeriousnessId == 0;
	my $tb = $dbh->selectall_hashref("SELECT id as ecdcDrugYearSeriousnessId, ecdcDrugId, ecdcYearId, ecdcSeriousness, totalCases FROM ecdc_drug_year_seriousness WHERE id > $latestEcdcDrugYearSeriousnessId", 'ecdcDrugYearSeriousnessId');
	for my $ecdcDrugYearSeriousnessId (sort{$a <=> $b} keys %$tb) {
		$latestEcdcDrugYearSeriousnessId = $ecdcDrugYearSeriousnessId;
		my $ecdcDrugId = %$tb{$ecdcDrugYearSeriousnessId}->{'ecdcDrugId'} // die;
		my $ecdcYearId = %$tb{$ecdcDrugYearSeriousnessId}->{'ecdcYearId'} // die;
		my $ecdcSeriousness = %$tb{$ecdcDrugYearSeriousnessId}->{'ecdcSeriousness'} // die;
		my $totalCases = %$tb{$ecdcDrugYearSeriousnessId}->{'totalCases'} // die;
		$ecdcDrugYearSeriousnesses{$ecdcDrugId}->{$ecdcYearId}->{$ecdcSeriousness}->{'ecdcDrugYearSeriousnessId'} = $ecdcDrugYearSeriousnessId;
		$ecdcDrugYearSeriousnesses{$ecdcDrugId}->{$ecdcYearId}->{$ecdcSeriousness}->{'totalCases'} = $totalCases;
	}
}

sub get_ecdc_notices_earliest_year_listed {
	my ($currentDrugs, $totalDrugs) = (0, 0);
	for my $internalId (sort{$a <=> $b} keys %ecdcDrugs) {
		my $updateTimestamp = $ecdcDrugs{$internalId}->{'updateTimestamp'} // next;
		next if $ecdcDrugs{$internalId}->{'aeFromEcdcYearId'};
		my $ecdcDrugName    = $ecdcDrugs{$internalId}->{'name'}   // die;
		if ($covidOnly eq 'true') {
			next if $ecdcDrugName !~ /COVID-19/;
		}
		my $isIndexed    = $ecdcDrugs{$internalId}->{'isIndexed'} // die;
		if ($isIndexedOnly eq 'true') {
			next unless $isIndexed;
		}
		$totalDrugs++;
	}
	for my $internalId (sort{$a <=> $b} keys %ecdcDrugs) {
		my $ecdcDrugId             = $ecdcDrugs{$internalId}->{'ecdcDrugId'}             // die;
		my $updateTimestamp        = $ecdcDrugs{$internalId}->{'updateTimestamp'}        // next;
		next if $ecdcDrugs{$internalId}->{'aeFromEcdcYearId'};
		my $name   = $ecdcDrugs{$internalId}->{'name'}   // die;
		if ($covidOnly eq 'true') {
			next if $name !~ /COVID-19/;
		}
		my $isIndexed    = $ecdcDrugs{$internalId}->{'isIndexed'} // die;
		if ($isIndexedOnly eq 'true') {
			next unless $isIndexed;
		}
		$currentDrugs++;
		my $currentDatetime = time::current_datetime();
		STDOUT->printflush("\r$currentDatetime - Getting [Drugs' Notices Earliest Adverse Effects] - [$currentDrugs / $totalDrugs]");
		my $url    = $ecdcDrugs{$internalId}->{'url'}    // die;
		# say "\nurl : $url";
		# say "$ecdcDrugId - $internalId - $name";
		$driver->get($url);

		expect_line_listing();

		# Clicking Line Listing & Downloading every notice.
		select_line_listing();

		# Listing available years. 
		my %years = list_years($url);

		# Identifying earliest year with reports.
		my $aeFromEcdcYearId = identify_earliest_year($ecdcDrugId, $url, %years);
		die unless $aeFromEcdcYearId;
		my $sth = $dbh->prepare("UPDATE ecdc_drug SET aeFromEcdcYearId = $aeFromEcdcYearId WHERE id = $ecdcDrugId");
		$sth->execute() or die $sth->err();
		$ecdcDrugs{$internalId}->{'aeFromEcdcYearId'} = $aeFromEcdcYearId;
	}
	say "" if $totalDrugs;
}

sub expect_line_listing {
	my $lineListingButton;
	while (!$lineListingButton) {
		my $content = $driver->get_page_source;
		my $tree    = HTML::Tree->new();
		$tree->parse($content);
		$lineListingButton = $tree->look_down(title=>'Line Listing');
		if (!$lineListingButton) {
			sleep 1;
		}
	}
	# say "Line listing is now available ...";
}

sub select_line_listing {

	# Clicking Line Listing.
	# say "Line Listing has been found ; clicking it ...";
	my $lineListingButton = $driver->find_element("(//table[\@id='dashboard_page_6_tab'])[1]");
	$lineListingButton->click();
	sleep 1;

	my $content = $driver->get_page_source;
	my $tree    = HTML::Tree->new();
	$tree->parse($content);
}

sub list_years {
	my ($url) = @_;

	# Locating Gateway Date button ID.
	my %optionsIds = ();
	while (!keys %optionsIds) {
		my $content = $driver->get_page_source;
		my $tree    = HTML::Tree->new();
		$tree->parse($content);
		my @labels  = $tree->find('label');
		my ($selectId);
		my $attempts = 0;
		while (!$selectId) {
			for my $label (@labels) {
				next unless $label->attr_get_i('title');
				my $title = $label->attr_get_i('title');
				if ($title eq 'Gateway Date') {
					my $for = $label->attr_get_i('for');
					# say "for      : $for";
					($selectId) = $for =~ /saw_(.*)_op/;
					# say "selectId : $selectId";
					last;
				}
			}
			if (!$selectId) {
				$attempts++;
				sleep 1;
				say "More resilience to code here 2" if $attempts > 30;
				c_e() if $attempts > 30;
			}
		}
		# say "selectId : $selectId";

		# Selecting Gateway Date button.
		my $gatewayDateButton = $driver->find_element("(//img[\@id='saw_" . $selectId . "_1_dropdownIcon'])[1]");
		$gatewayDateButton->click();

		# Parsing years dropdown options.
		my $fetchingAttempts = 0;
		while (!keys %optionsIds) {
			my $div        = get_dropdown_div();
			my @divs       = $div->look_down(class=>"masterMenuItem promptMenuOption");
			for my $div (@divs) {
				my $label  = $div->as_trimmed_text;
				unless (exists $ecdcYears{$label}->{'ecdcYearId'}) {
					my $sth = $dbh->prepare("INSERT INTO ecdc_year (name) VALUES (?)");
					$sth->execute($label) or die $sth->err();
					ecdc_years();
				}
				my $ecdcYearId = $ecdcYears{$label}->{'ecdcYearId'} // die;
				$optionsIds{$label} = $ecdcYearId;
			}
			if (!keys %optionsIds) {
				sleep 1;
				$fetchingAttempts++;
				if ($fetchingAttempts > 30) {
					say "Failed 30 times ; trying again ...";

					$driver->get($url);

					expect_line_listing();

					# Clicking Line Listing & Downloading every notice.
					select_line_listing();
				}
			}
		}
	}

	# Incrementing current year (selected by default)
	my $currentDatetime = time::current_datetime();
	my ($currentYear)   = split ' ', $currentDatetime;
	($currentYear)      = split '-', $currentYear;
	unless (exists $ecdcYears{$currentYear}->{'ecdcYearId'}) {
		my $sth = $dbh->prepare("INSERT INTO ecdc_year (name) VALUES (?)");
		$sth->execute($currentYear) or die $sth->err();
		ecdc_years();
	}
	my $ecdcYearId = $ecdcYears{$currentYear}->{'ecdcYearId'} // die;
	$optionsIds{$currentYear} = $ecdcYearId;
	sleep 1;
	return %optionsIds;
}

sub get_dropdown_div {
	my $content    = $driver->get_page_source;
	my $tree       = HTML::Tree->new();
	$tree->parse($content);
	my $div        = $tree->look_down(class=>"floatingWindowDiv");
	while (!$div) {
		$content   = $driver->get_page_source;
		my $tree   = HTML::Tree->new();
		$tree->parse($content);
		$div       = $tree->look_down(class=>"floatingWindowDiv");
		sleep 1;
	}
	return $div;
}

sub click_age_group {
	# Locating Age Group button ID.
	my $content = $driver->get_page_source;
	my $tree    = HTML::Tree->new();
	$tree->parse($content);
	my @labels  = $tree->find('label');
	my ($selectId);
	for my $label (@labels) {
		next unless $label->attr_get_i('title');
		my $title = $label->attr_get_i('title');
		if ($title eq 'Age Group') {
			my $for = $label->attr_get_i('for');
			# say "for      : $for";
			($selectId) = $for =~ /saw_(.*)_op/;
			# say "selectId : $selectId";
			last;
		}
	}

	# Selecting Gateway Date button.s
	my $ageGroupButton = $driver->find_element("(//img[\@id='saw_" . $selectId . "_1_dropdownIcon'])[1]");
	# say "clicking 1";
	$ageGroupButton->click();
	sleep 1;
}

sub list_age_groups {

	click_age_group();

	# Parsing years dropdown options.
	my %optionsIds = ();
	my $attempts = 0;
	while (!keys %optionsIds) {
		my $div        = get_dropdown_div();
		my @divs       = $div->look_down(class=>"masterMenuItem promptMenuOption");
		for my $div (@divs) {
			my $label  = $div->as_trimmed_text;
			$optionsIds{$label} = 1;
		}
		if (!keys %optionsIds) {
			sleep 1;
			$attempts++;
			say "More resilience to code here 4" if $attempts > 30;
			c_e() if $attempts > 30;
		}
	}

	sleep 1;
	return %optionsIds;
}

sub identify_earliest_year {
	my ($ecdcDrugId, $url, %years) = @_;
	for my $year (sort{$a <=> $b} keys %years) {
		my $ecdcYearId = $years{$year} // die;

		# Selecting targeted year.
		select_year($year);
		run_line_report();
		sleep 1;

		# Switching to tab & identifying if we have reports listed on this gateway year.
		my $handles = $driver->get_window_handles;
		$driver->switch_to_window($handles->[1]);

		# Downloading all reports on CSV format.
		my $content = $driver->get_page_source;
		my $tree    = HTML::Tree->new();
		$tree->parse($content);

		# Attempting to find if "No results" is rendered.
		if (!$tree->look_down(title=>"No Results")) {

			# If the year is 1900, we set the dedicated 'error' tag.
			if ($year eq '1900') {
				my $sth = $dbh->prepare("UPDATE ecdc_drug SET hasNullGateYear = 1 WHERE id = $ecdcDrugId");
				$sth->execute() or die $sth->err();
			} else {

				# Closing tab & returning earliest year to Line Listing.
				$driver->close;
				$driver->switch_to_window($handles->[0]);
				return $ecdcYearId;
			}
		}


		# Closing tab & returning to Line Listing.
		$driver->close;
		$driver->switch_to_window($handles->[0]);

		# Listing years for re-selection.
		list_years($url);
	}

	# Shouldn't arrive here.
	c_e();
}

sub select_year {
	my ($year)  = @_;
	my $content = $driver->get_page_source;
	my $tree    = HTML::Tree->new();
	$tree->parse($content);
	my $button  = $tree->look_down(title => $year);
	while (!$button) {
		my $content = $driver->get_page_source;
		my $tree    = HTML::Tree->new();
		$tree->parse($content);
		$button     = $tree->look_down(title => $year);
	}
	my $yearButton  = $driver->find_element("(//div[\@title='" . $year . "'])[1]");
	$yearButton->click();
	sleep 2;
}

sub run_line_report {
	my $runButton = $driver->find_element("(//a[\@name='SectionElements'])[1]");
	$runButton->click();
	sleep 2;
}

sub ecdc_notices {
	my $currentDatetime = time::current_datetime();
	say "$currentDatetime - Loading [Known Notices]" if $latestEcdcNoticeId == 0;
	my $tb = $dbh->selectall_hashref("SELECT id as ecdcNoticeId, internalId, ICSRUrl, pdfScrappingTimestamp, ecdcSeriousness, ecdcReporterType, ecdcYearId FROM ecdc_notice WHERE id > $latestEcdcNoticeId", 'ecdcNoticeId');
	for my $ecdcNoticeId (sort{$a <=> $b} keys %$tb) {
		$latestEcdcNoticeId       = $ecdcNoticeId;
		my $internalId            = %$tb{$ecdcNoticeId}->{'internalId'}            // die;
		my $ICSRUrl               = %$tb{$ecdcNoticeId}->{'ICSRUrl'}               // die;
		my $ecdcYearId            = %$tb{$ecdcNoticeId}->{'ecdcYearId'}            // die;
		my $ecdcSeriousness       = %$tb{$ecdcNoticeId}->{'ecdcSeriousness'}       // die;
		my $ecdcReporterType      = %$tb{$ecdcNoticeId}->{'ecdcReporterType'}      // die;
		my $pdfScrappingTimestamp = %$tb{$ecdcNoticeId}->{'pdfScrappingTimestamp'};
		$ecdcNotices{$internalId}->{'ecdcNoticeId'}          = $ecdcNoticeId;
		$ecdcNotices{$internalId}->{'ecdcYearId'}            = $ecdcYearId;
		$ecdcNotices{$internalId}->{'ecdcSeriousness'}       = $ecdcSeriousness;
		$ecdcNotices{$internalId}->{'ecdcReporterType'}      = $ecdcReporterType;
		$ecdcNotices{$internalId}->{'ICSRUrl'}               = $ICSRUrl;
		$ecdcNotices{$internalId}->{'pdfScrappingTimestamp'} = $pdfScrappingTimestamp;
	}
}

sub ecdc_drug_notices {
	my $currentDatetime = time::current_datetime();
	say "$currentDatetime - Loading [Known Drugs / Notices Relations]" if $latestEcdcDrugNoticeId == 0;
	my $tb = $dbh->selectall_hashref("SELECT id as ecdcDrugNoticeId, ecdcDrugId, ecdcNoticeId FROM ecdc_drug_notice WHERE id > $latestEcdcDrugNoticeId", 'ecdcDrugNoticeId');
	for my $ecdcDrugNoticeId (sort{$a <=> $b} keys %$tb) {
		$latestEcdcDrugNoticeId = $ecdcDrugNoticeId;
		my $ecdcDrugId = %$tb{$ecdcDrugNoticeId}->{'ecdcDrugId'} // die;
		my $ecdcNoticeId = %$tb{$ecdcDrugNoticeId}->{'ecdcNoticeId'} // die;
		$ecdcDrugNotices{$ecdcDrugId}->{$ecdcNoticeId}->{'ecdcDrugNoticeId'} = $ecdcDrugNoticeId;
	}
}

sub ecdc_reactions {
	my $tb = $dbh->selectall_hashref("SELECT id as ecdcReactionId, name FROM ecdc_reaction WHERE id > $latestEcdcReactionId", 'ecdcReactionId');
	for my $ecdcReactionId (sort{$a <=> $b} keys %$tb) {
		$latestEcdcReactionId = $ecdcReactionId;
		my $name = %$tb{$ecdcReactionId}->{'name'} // die;
		$ecdcReactions{$name}->{'ecdcReactionId'} = $ecdcReactionId;
	}
}

sub ecdc_reaction_outcomes {
	my $tb = $dbh->selectall_hashref("SELECT id as ecdcReactionOutcomeId, name FROM ecdc_reaction_outcome WHERE id > $latestEcdcReactionOutcomeId", 'ecdcReactionOutcomeId');
	for my $ecdcReactionOutcomeId (sort{$a <=> $b} keys %$tb) {
		$latestEcdcReactionOutcomeId = $ecdcReactionOutcomeId;
		my $name = %$tb{$ecdcReactionOutcomeId}->{'name'} // die;
		$ecdcReactionOutcomes{$name}->{'ecdcReactionOutcomeId'} = $ecdcReactionOutcomeId;
	}
}

sub ecdc_reaction_seriousnesses {
	my $tb = $dbh->selectall_hashref("SELECT id as ecdcReactionSeriousnessId, name FROM ecdc_reaction_seriousness WHERE id > $latestEcdcReactionSeriousnessId", 'ecdcReactionSeriousnessId');
	for my $ecdcReactionSeriousnessId (sort{$a <=> $b} keys %$tb) {
		$latestEcdcReactionSeriousnessId = $ecdcReactionSeriousnessId;
		my $name = %$tb{$ecdcReactionSeriousnessId}->{'name'} // die;
		$ecdcReactionSeriousnesses{$name}->{'ecdcReactionSeriousnessId'} = $ecdcReactionSeriousnessId;
	}
}

sub ecdc_notice_reactions {
	my $currentDatetime = time::current_datetime();
	say "$currentDatetime - Loading [Known Notices / Reactions Relations]" if $latestEcdcNoticeReactionId == 0;
	my $tb = $dbh->selectall_hashref("SELECT id as ecdcNoticeReactionId, ecdcNoticeId, ecdcReactionId FROM ecdc_notice_reaction WHERE id > $latestEcdcNoticeReactionId", 'ecdcNoticeReactionId');
	for my $ecdcNoticeReactionId (sort{$a <=> $b} keys %$tb) {
		$latestEcdcNoticeReactionId = $ecdcNoticeReactionId;
		my $ecdcNoticeId = %$tb{$ecdcNoticeReactionId}->{'ecdcNoticeId'} // die;
		my $ecdcReactionId = %$tb{$ecdcNoticeReactionId}->{'ecdcReactionId'} // die;
		$ecdcNoticeReactions{$ecdcNoticeId}->{$ecdcReactionId}->{'ecdcNoticeReactionId'} = $ecdcNoticeReactionId;
	}
}

sub get_ecdc_notices {
	my ($currentDrugs, $totalDrugs) = (0, 0);
	for my $internalId (sort{$a <=> $b} keys %ecdcDrugs) {
		my $ecdcDrugId             = $ecdcDrugs{$internalId}->{'ecdcDrugId'}             // die;
		my $updateTimestamp        = $ecdcDrugs{$internalId}->{'updateTimestamp'}        // next;
		next unless (!$ecdcDrugs{$internalId}->{'reportsUpdateTimestamp'} ||
			$ecdcDrugs{$internalId}->{'reportsUpdateTimestamp'} ne $updateTimestamp);
		my $ecdcDrugName           = $ecdcDrugs{$internalId}->{'name'}   // die;
		if ($covidOnly eq 'true') {
			next if $ecdcDrugName !~ /COVID-19/;
		}
		my $isIndexed    = $ecdcDrugs{$internalId}->{'isIndexed'} // die;
		if ($isIndexedOnly eq 'true') {
			next unless $isIndexed;
		}
		$totalDrugs++;
	}
	for my $internalId (sort{$a <=> $b} keys %ecdcDrugs) {
		my $ecdcDrugName     = $ecdcDrugs{$internalId}->{'name'}   // die;
		if ($covidOnly eq 'true') {
			next if $ecdcDrugName !~ /COVID-19/;
		}
		my $isIndexed        = $ecdcDrugs{$internalId}->{'isIndexed'} // die;
		if ($isIndexedOnly eq 'true') {
			next unless $isIndexed;
		}
		my $ecdcDrugId       = $ecdcDrugs{$internalId}->{'ecdcDrugId'}       // die;
		my $updateTimestamp  = $ecdcDrugs{$internalId}->{'updateTimestamp'}  // next;
		my $aeFromEcdcYearId = $ecdcDrugs{$internalId}->{'aeFromEcdcYearId'} // die;
		my $hasNullGateYear  = $ecdcDrugs{$internalId}->{'hasNullGateYear'}  // die;
		next unless (!$ecdcDrugs{$internalId}->{'reportsUpdateTimestamp'} ||
			$ecdcDrugs{$internalId}->{'reportsUpdateTimestamp'} ne $updateTimestamp);
		my $currentDatetime  = time::current_datetime();
		$currentDrugs++;
		# next unless $ecdcDrugId == 1133;
		STDOUT->printflush("\r$currentDatetime - Getting [Drugs' Notices] - [$currentDrugs / $totalDrugs] - [$ecdcDrugName]                                             ");
		my $url              = $ecdcDrugs{$internalId}->{'url'}    // die;
		# say "\nurl : $url";
		# say "$ecdcDrugId - $internalId - $name - $url";

		browse_years_seriousness($url, $ecdcDrugId, $ecdcDrugName, $aeFromEcdcYearId, $hasNullGateYear, $currentDrugs, $totalDrugs);

		my $earliestAERTimestamp = $ecdcDrugs{$internalId}->{'earliestAERTimestamp'};
		if (!$earliestAERTimestamp) {

			# Fetching earliest notice linked to this drug.
			my $eDNTSql = "
				SELECT
				    ecdc_drug_notice.ecdcNoticeId,
				    ecdc_notice.receiptTimestamp as earliestAERTimestamp
				FROM ecdc_drug_notice
					LEFT JOIN ecdc_notice ON ecdc_notice.id = ecdc_drug_notice.ecdcNoticeId
				WHERE ecdcDrugId = $ecdcDrugId ORDER BY ecdc_notice.receiptTimestamp ASC LIMIT 1";
			my $eDNTb = $dbh->selectrow_hashref($eDNTSql, undef);
			my $earliestAERTimestamp = %$eDNTb{'earliestAERTimestamp'} // die;
			my $sth = $dbh->prepare("UPDATE ecdc_drug SET earliestAERTimestamp = $earliestAERTimestamp WHERE id = $ecdcDrugId");
			$sth->execute() or die $sth->err();
		}

		# Updating drug's total cases & report status.
		my $eDNTSql = "
			SELECT
				count(ecdc_drug_notice.id) as totalCasesScrapped
			FROM ecdc_drug_notice
				LEFT JOIN ecdc_notice ON ecdc_notice.id = ecdc_drug_notice.ecdcNoticeId
			WHERE ecdcDrugId = $ecdcDrugId";
		my $eDNTb = $dbh->selectrow_hashref($eDNTSql, undef);
		my $totalCasesScrapped = %$eDNTb{'totalCasesScrapped'} // die;
		my $sth = $dbh->prepare("UPDATE ecdc_drug SET reportsUpdateTimestamp = $updateTimestamp, totalCasesScrapped = $totalCasesScrapped WHERE id = $ecdcDrugId");
		$sth->execute() or die $sth->err();
		# sleep 10;
		# c_e();
	}
	say "" if $totalDrugs;
}

sub browse_years_seriousness {
	say "browse_years_seriousness";
	my ($url, $ecdcDrugId, $ecdcDrugName, $aeFromEcdcYearId, $hasNullGateYear, $currentDrugs, $totalDrugs) = @_;
	my $aeFromEcdcYear  = $ecdcYearsFromIds{$aeFromEcdcYearId}->{'name'} // die;
	# say "ecdcDrugId       : $ecdcDrugId";
	# say "hasNullGateYear  : $hasNullGateYear";
	# say "aeFromEcdcYearId : $aeFromEcdcYearId";
	# say "aeFromEcdcYear   : $aeFromEcdcYear";

	# Refreshing product URL
	$driver->get($url);

	expect_line_listing();

	# Clicking Line Listing & Downloading every notice.
	select_line_listing();

	# Listing available years. 
	my %years = list_years($url);

	# Selecting each year one by one.
	my $totalYears        = keys %years;
	my $currentYear       = 0;
	for my $year (sort{$a <=> $b} keys %years) {
		$currentYear++;
		if (!$hasNullGateYear) {
			next if $year == 1900;
		}
		if ($year != 1900) {
			next if $year < $aeFromEcdcYear;
		}
		my $ecdcYearId = $years{$year} // die;
		next if exists $ecdcDrugYears{$ecdcDrugId}->{$ecdcYearId}->{'ecdcDrugYearId'};

		# Going through each incident seriousness.
		for my $ecdcSeriousness (sort{$a <=> $b} keys %ecdcSeriousness) {
			my $ecdcSeriousnessLabel = $ecdcSeriousness{$ecdcSeriousness} // die;
			my $currentDatetime = time::current_datetime();
			STDOUT->printflush("\r$currentDatetime - Getting [Drugs' Notices] - [$currentDrugs / $totalDrugs] - [$ecdcDrugName] - [$year] - [$ecdcSeriousnessLabel]                                             ");

			# Refreshing product URL
			$driver->get($url);

			expect_line_listing();

			# Clicking Line Listing & Downloading every notice.
			select_line_listing();

			list_years($url);

			# Selecting targeted year.
			select_year($year);

			my $totalCases;
			if ($ecdcDrugYearSeriousnesses{$ecdcDrugId}->{$ecdcYearId}->{$ecdcSeriousness}->{'totalCases'} && ($ecdcDrugYearSeriousnesses{$ecdcDrugId}->{$ecdcYearId}->{$ecdcSeriousness}->{'totalCases'} > 249000)) {
				$totalCases = browse_year_seriousness_by_age_groups($url, $ecdcDrugId, $ecdcDrugName, $aeFromEcdcYearId, $hasNullGateYear, $currentDrugs, $totalDrugs, $year, $ecdcYearId, $ecdcSeriousness, $ecdcSeriousnessLabel);
			} else {
				select_serious_dropdown();
				select_dropdown_option($ecdcSeriousnessLabel);
				select_serious_dropdown();
				run_line_report();
				$totalCases = parse_line_report($ecdcDrugId, $ecdcYearId, $ecdcSeriousness, $currentDrugs, $totalDrugs);
				die unless defined $totalCases;

				# If we have more than the limit of cases we browse the seriousness by age group.
				if ($totalCases > 249000) {
					$totalCases = browse_year_seriousness_by_age_groups($url, $ecdcDrugId, $ecdcDrugName, $aeFromEcdcYearId, $hasNullGateYear, $currentDrugs, $totalDrugs, $year, $ecdcYearId, $ecdcSeriousness, $ecdcSeriousnessLabel);
				}
			}

			# Updating current total for seriousness / year.
			unless (exists $ecdcDrugYearSeriousnesses{$ecdcDrugId}->{$ecdcYearId}->{$ecdcSeriousness}->{'ecdcDrugYearSeriousnessId'}) {
				my $sth = $dbh->prepare("INSERT INTO ecdc_drug_year_seriousness (ecdcDrugId, ecdcYearId, ecdcSeriousness, totalCases, updateTimestamp) VALUES ($ecdcDrugId, $ecdcYearId, $ecdcSeriousness, $totalCases, UNIX_TIMESTAMP())");
				$sth->execute() or die $sth->err();
				ecdc_drug_year_seriousnesses();
			} else {
				if ($ecdcDrugYearSeriousnesses{$ecdcDrugId}->{$ecdcYearId}->{$ecdcSeriousness}->{'totalCases'} != $totalCases) {
					my $ecdcDrugYearSeriousnessId = $ecdcDrugYearSeriousnesses{$ecdcDrugId}->{$ecdcYearId}->{$ecdcSeriousness}->{'ecdcDrugYearSeriousnessId'} // die;
					my $sth = $dbh->prepare("UPDATE ecdc_drug_year_seriousness SET totalCases = $totalCases, updateTimestamp = UNIX_TIMESTAMP() WHERE id = $ecdcDrugYearSeriousnessId");
					$sth->execute() or die $sth->err();
					$ecdcDrugYearSeriousnesses{$ecdcDrugId}->{$ecdcYearId}->{$ecdcSeriousness}->{'totalCases'} = $totalCases;
				}
			}
		}

		# If not the latest one ; setting the year as indexed for this drug.
		unless ($currentYear == $totalYears) {

			my $sth = $dbh->prepare("INSERT INTO ecdc_drug_year (ecdcDrugId, ecdcYearId) VALUES (?, ?)");
			$sth->execute($ecdcDrugId, $ecdcYearId) or die $sth->err();
			ecdc_drug_years();

			# Refreshing product URL
			$driver->get($url);

			expect_line_listing();

			# Clicking Line Listing & Downloading every notice.
			select_line_listing();

			# Listing available years. 
			list_years($url);
		}
	}
}

sub browse_year_seriousness_by_age_groups {
	say "browse_year_seriousness_by_age_groups";
	my ($url, $ecdcDrugId, $ecdcDrugName, $aeFromEcdcYearId, $hasNullGateYear, $currentDrugs, $totalDrugs, $year, $ecdcYearId, $ecdcSeriousness, $ecdcSeriousnessLabel) = @_;
	my $aeFromEcdcYear  = $ecdcYearsFromIds{$aeFromEcdcYearId}->{'name'} // die;
	# say "ecdcDrugId       : $ecdcDrugId";
	# say "hasNullGateYear  : $hasNullGateYear";
	# say "aeFromEcdcYearId : $aeFromEcdcYearId";
	# say "aeFromEcdcYear   : $aeFromEcdcYear";

	# Refreshing product URL
	$driver->get($url);

	expect_line_listing();

	# Clicking Line Listing & Downloading every notice.
	select_line_listing();

	# Going through each incident age group.
	my %ageGroups = list_age_groups();
	# p %ageGroups;

	my $cumulatedTotal = 0;
	for my $ageGroup (sort keys %ageGroups) {
		my $currentDatetime = time::current_datetime();
		STDOUT->printflush("\r$currentDatetime - Getting [Drugs' Notices] - [$currentDrugs / $totalDrugs] - [$ecdcDrugName] - [$year] - [$ecdcSeriousnessLabel] - [$ageGroup]                                             ");

		# Refreshing product URL
		$driver->get($url);

		expect_line_listing();

		# Clicking Line Listing & Downloading every notice.
		select_line_listing();

		# Selecting targeted year.
		list_years($url);
		select_year($year);
		sleep 1;

		select_serious_dropdown();
		select_dropdown_option($ecdcSeriousnessLabel);
		select_serious_dropdown();
		sleep 2;

		# Going through each incident age group.

		# Selecting age group.
		my $ecdcAgeGroup = age_group_to_enum($ageGroup);
		list_age_groups();
		sleep 2;
		select_dropdown_option($ageGroup);
		sleep 2;
		click_age_group();
		sleep 2;
		# say "running report";
		run_line_report();
		my $totalCases = parse_line_report($ecdcDrugId, $ecdcYearId, $ecdcSeriousness, $currentDrugs, $totalDrugs, $ecdcAgeGroup);
		die unless defined $totalCases;
		if ($totalCases > 249000) {
			$totalCases = browse_year_seriousness_age_group_by_sexes($url, $ecdcDrugId, $ecdcDrugName, $aeFromEcdcYearId, $hasNullGateYear, $currentDrugs, $totalDrugs, $year, $ecdcYearId, $ecdcSeriousness, $ecdcSeriousnessLabel, $ageGroup, $ecdcAgeGroup);
		}
		$cumulatedTotal += $totalCases;
	}

	return $cumulatedTotal;
}

sub age_group_to_enum {
	my ($ageGroup) = @_;
	my $ecdcAgeGroup;
	if ($ageGroup eq '0-1 Month') {
		$ecdcAgeGroup = 1;
	} elsif ($ageGroup eq '2 Months - 2 Years') {
		$ecdcAgeGroup = 2;
	} elsif ($ageGroup eq '3-11 Years') {
		$ecdcAgeGroup = 3;
	} elsif ($ageGroup eq '12-17 Years') {
		$ecdcAgeGroup = 4;
	} elsif ($ageGroup eq '18-64 Years') {
		$ecdcAgeGroup = 5;
	} elsif ($ageGroup eq '65-85 Years') {
		$ecdcAgeGroup = 6;
	} elsif ($ageGroup eq 'More than 85 Years') {
		$ecdcAgeGroup = 7;
	} elsif ($ageGroup eq 'Not Specified') {
		$ecdcAgeGroup = 8;
	} else {
		die "ecdcAgeGroup : [$ecdcAgeGroup]";
	}
	return $ecdcAgeGroup;
}

sub select_serious_dropdown {

	# Locating Seriousness button ID.
	my $content = $driver->get_page_source;
	my $tree    = HTML::Tree->new();
	$tree->parse($content);
	my @labels  = $tree->find('label');
	my ($selectId);
	for my $label (@labels) {
		next unless $label->attr_get_i('title');
		my $title = $label->attr_get_i('title');
		if ($title eq 'Seriousness') {
			my $for = $label->attr_get_i('for');
			# say "for      : $for";
			($selectId) = $for =~ /saw_(.*)_op/;
			# say "selectId : $selectId";
			last;
		}
	}

	# Selecting Serious Incidents.
	my $seriousnessButton = $driver->find_element("(//img[\@id='saw_" . $selectId . "_1_dropdownIcon'])[1]");
	$seriousnessButton->click();
	sleep 2;
}

sub select_dropdown_option {
	my ($option)   = @_;
	my $content    = $driver->get_page_source;
	my $tree       = HTML::Tree->new();
	$tree->parse($content);
	# open my $out, '>', 'tree.html';
	# say $out $tree->as_HTML('<>&', "\t");
	# close $out;
	my $div        = get_dropdown_div();
	my @divs       = $div->look_down(class=>"masterMenuItem promptMenuOption");
	my %optionsIds = ();
	for my $div (@divs) {
		my $input  = $div->find('input');
		my $id     = $input->attr_get_i('id');
		my $label  = $div->as_trimmed_text;
		$optionsIds{$label} = $id;
		# say "$id - $label";
	}
	# p%optionsIds;
	my $optionId   = $optionsIds{$option} // die;
	my $optionButton = $driver->find_element("(//input[\@id='" . $optionId . "'])[1]");
	$optionButton->click();
	sleep 2;
}

sub parse_line_report {
	my ($ecdcDrugId, $ecdcYearId, $ecdcSeriousness, $currentDrugs, $totalDrugs, $fetchedEcdcAgeGroup, $fetchedEcdcSexGroup, $fetchedEcdcGeoOriginGroup, $fetchedEcdcReporterTypeGroup) = @_;
	# p$driver;
	my $handles = $driver->get_window_handles;
	$driver->switch_to_window($handles->[1]);

	# Downloading all reports on CSV format.
	my $content = $driver->get_page_source;
	my $tree    = HTML::Tree->new();
	$tree->parse($content);
	my $csvUrl;
	my $attempts = 0;
	while (!$csvUrl) {
		my $content = $driver->get_page_source;
		my $tree    = HTML::Tree->new();
		$tree->parse($content);

		# Verifies that the search isn't currently ongoing.
		my $isSearching = 0;
		my $search = $tree->look_down(class=>"ViewCell");
		if ($search) {
			$search = $search->as_trimmed_text;
			if ($search eq 'Searching... To cancel, click here.') {
				$isSearching = 1;
			}
		}

		# If the search isn't ongoing, trying to find the export to CSV url.
		if ($isSearching != 1) {
			$attempts++;
			# open my $out, '>', 'tree.html';
			# say $out $tree->as_HTML('<>&', "\t");
			# close $out;
			my @as = $tree->look_down(name=>"SectionElements");
			for my $aHref (@as) {
				my @tbodys = $aHref->find('tbody');
				next unless scalar @tbodys == 1;
				my @tds    = $aHref->find('td');
				my $label  = $tds[1]->as_trimmed_text;
				next unless $label eq 'CSV';
				my $id     = $aHref->attr_get_i('onclick');
				($id)      = $id =~ /return Download\('(.*)', null, '/;
				$csvUrl    = 'https://dap.ema.europa.eu/analyticsSOAP/' . $id;
				# say "id : $id";
				last;
			}
			sleep 1;
			last if $attempts > 20;
		}
	}

	# If no url is found, search returned not results.
	unless ($csvUrl) {

		# Closing tab & returning to Line Listing.
		$driver->close;
		$driver->switch_to_window($handles->[0]);
		return 0;
	}

	# say "csvUrl : $csvUrl";
	$driver->get($csvUrl);

	# Verifies if the file's download is completed.
	while (!-f $lineListingReportPath) {
		# say "Awaiting for file download";
		sleep 1;
	}
	die unless -f $lineListingReportPath;

	# Parses the relevant CSV data.
	# say "";
	my $exportFile = "$exportsPdfDir/$ecdcDrugId" . "_$ecdcYearId" . "_$ecdcSeriousness.csv";
	open my $in, '<', $lineListingReportPath;
	if ($fetchedEcdcAgeGroup && $fetchedEcdcSexGroup && $fetchedEcdcGeoOriginGroup && $fetchedEcdcReporterTypeGroup) {
		$exportFile = "$exportsPdfDir/$ecdcDrugId" . "_$ecdcYearId" . "_$ecdcSeriousness" . "_$fetchedEcdcAgeGroup" . "_$fetchedEcdcSexGroup" . "_$fetchedEcdcGeoOriginGroup" . "_$fetchedEcdcReporterTypeGroup.csv";
	} elsif ($fetchedEcdcAgeGroup && $fetchedEcdcSexGroup && $fetchedEcdcGeoOriginGroup) {
		$exportFile = "$exportsPdfDir/$ecdcDrugId" . "_$ecdcYearId" . "_$ecdcSeriousness" . "_$fetchedEcdcAgeGroup" . "_$fetchedEcdcSexGroup" . "_$fetchedEcdcGeoOriginGroup.csv";
	} elsif ($fetchedEcdcAgeGroup && $fetchedEcdcSexGroup) {
		$exportFile = "$exportsPdfDir/$ecdcDrugId" . "_$ecdcYearId" . "_$ecdcSeriousness" . "_$fetchedEcdcAgeGroup" . "_$fetchedEcdcSexGroup.csv";
	} elsif ($fetchedEcdcAgeGroup) {
		$exportFile = "$exportsPdfDir/$ecdcDrugId" . "_$ecdcYearId" . "_$ecdcSeriousness" . "_$fetchedEcdcAgeGroup.csv";
	}
	# say "Parsing [$exportFile]";
	open my $out, '>', $exportFile;
	my $totalCases = 0;
	my $currentDatetime = time::current_datetime();
	while (<$in>) {
		chomp $_;
		say $out $_;
		my ($noticeInternalId, $ecdcReportType, $receiptDate, $ecdcReporterType, $ecdcGeographicalOrigin, $ICSRUrl, $ecdcAgeGroup, $ecdcSex);
		my @elems               = split ',', $_;
		# die;
		$noticeInternalId       = $elems[0] // die;
		next unless $noticeInternalId =~ /EU-EC-/;
		if (scalar @elems != 14) {
			# say $_;
			# p@elems;
			my $elemIn  = 0;
			my $elemNum = 0;
			my %elems   = ();
			for my $elem (@elems) {
				# say "elemNum : $elemNum";
				# say "elem    : $elem";
				my $totalQuotes   = 0;
				my $quotesArePair = 0;
				if ($elem =~ /\"/) {
					my @str = split '', $elem;
					for my $char (@str) {
						if ($char eq '"') {
							$totalQuotes++;
						}
					}
					my $sumOfQuotesAvg    = $totalQuotes / 2;
					my $sumOfQuotesAvgInt = int($totalQuotes / 2);
					if ($sumOfQuotesAvg == $sumOfQuotesAvgInt) {
						$quotesArePair = 1;
					}
				}
				if (exists $elems{$elemNum}) {
					$elems{$elemNum} .= $elem;
				} else {
					$elems{$elemNum} = $elem;
				}
				if ($elem =~ /\"/ && $totalQuotes == 1 && $quotesArePair == 0) {
					if ($elemIn == 0) {
						# say "1";
						$elemIn = 1;
					} else {
						# say "2";
						$elemIn = 0;
						$elemNum++;
					}
				} else {
					if ($elemIn == 0) {
						# say "3";
						$elemNum++;
					} else {
						# say "4";
					}
				}
			}
			# p%elems;
			@elems = (); 
			for my $elemNum (sort{$a <=> $b} keys %elems) {
				my $elem = $elems{$elemNum} // die;
				push @elems, $elem;
			}
			# p@elems;
			# die;
		}
		$totalCases++;
		STDOUT->printflush("\r$currentDatetime - Parsing File - [$totalCases] cases parsed");
		$ecdcReportType         = $elems[1] // die;
		$ecdcReportType         = ecdc_report_type_to_enum($ecdcReportType);
		$receiptDate            = $elems[2] // die;
		$ecdcReporterType       = $elems[3] // die;
		$ecdcReporterType       = ecdc_reporter_type_to_enum($ecdcReporterType);
		$ecdcGeographicalOrigin = $elems[4] // die;
		$ecdcGeographicalOrigin = ecdc_geo_origin_to_enum($ecdcGeographicalOrigin);
		my $latestElem          = scalar @elems;
		$latestElem             = $latestElem - 1;
		$ecdcSex                = $elems[9] // die;
		my $ecdcSexId           = $ecdcSexs{$ecdcSex}->{'ecdcSexId'} // die;
		$ICSRUrl                = $elems[$latestElem] // die;
		my $faultyNoticeDetailsParsing = 0;
		my %noticeReactions = ();
		my %suspectDrugs = ();
		unless (scalar @elems == 14) {
			# p@elems;
			# @elems               = split ',', $_;
			# p@elems;
			$faultyNoticeDetailsParsing = 1;
			# die;
		} else {
			my $reactionsList = $elems[10] // die;
			my $suspectDrugs  = $elems[11] // die;
			$ecdcAgeGroup     = $elems[6]  // die;
			$reactionsList    =~ s/\"//g;
			$suspectDrugs     =~ s/\"//g;
			my @reactionsList = split '<BR>', $reactionsList;
			for my $reactionData (@reactionsList) {
				next unless $reactionData;
				# say "reactionData : $reactionData";
				my ($reaction, $outcomeData) = split ' \(', $reactionData;
				($outcomeData, undef) = split '\)', $outcomeData;
				my @el = split ' - ', $outcomeData;
				my ($duration, $outcome, $seriousnessCriteria);
				if (!$el[0] || !$el[1]) {
					$duration            = 'n/a';
					$outcome             = 'Unknown';
					$seriousnessCriteria = 'Unknown';
				} else {
					$duration            = $el[0] // die;
					$outcome             = $el[1] // die;
					$seriousnessCriteria = $el[2] // 'Unknown';
				}
				# $seriousnessCriterias{$seriousnessCriteria}++;
				# $reactions{$reaction}++;
				# $outcomes{$outcome}++;
				# $durations{$duration}++;
				$noticeReactions{$reaction}->{'outcome'} = $outcome;
				$noticeReactions{$reaction}->{'seriousnessCriteria'} = $seriousnessCriteria;
				$noticeReactions{$reaction}->{'duration'} = $duration;
				# say "reaction            : $reaction";
				# say "duration            : $duration";
				# say "outcome             : $outcome";
				# say "seriousnessCriteria : $seriousnessCriteria";
				# p@el;
				# die;
			}
		}

		# Converting age group to Enum.
		$ecdcAgeGroup = 'Not Specified' if !$ecdcAgeGroup;
		$ecdcAgeGroup = age_group_to_enum($ecdcAgeGroup);

		# p%noticeReactions;
		# p@reactionsList;
		# die;
		(undef,
			$ICSRUrl)        = split 'href=""', $ICSRUrl;
		($ICSRUrl, undef)    = split '""', $ICSRUrl;
		my $receiptTimestamp = time::datetime_to_timestamp($receiptDate);
		unless (exists $ecdcNotices{$noticeInternalId}->{'ecdcNoticeId'}) {
			my $pdfPath = "$noticesPdfDir/$noticeInternalId" . '.pdf';
			# say "noticeInternalId       : $noticeInternalId";
			# say "receiptDate            : $receiptDate";
			# say "receiptTimestamp       : $receiptTimestamp";
			# say "ecdcReportType         : $ecdcReportType";
			# say "ecdcReporterType       : $ecdcReporterType";
			# say "ecdcGeographicalOrigin : $ecdcGeographicalOrigin";
			# say "ICSRUrl                : $ICSRUrl";
			# say "pdfPath                : $pdfPath";
			my $sth = $dbh->prepare("INSERT INTO ecdc_notice (internalId, ecdcYearId, ecdcSeriousness, receiptTimestamp, ecdcReportType, ecdcReporterType, ecdcGeographicalOrigin, ICSRUrl, pdfPath, faultyNoticeDetailsParsing, ecdcAgeGroup, ecdcSexId) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, $faultyNoticeDetailsParsing, ?, ?)");
			$sth->execute($noticeInternalId, $ecdcYearId, $ecdcSeriousness, $receiptTimestamp, $ecdcReportType, $ecdcReporterType, $ecdcGeographicalOrigin, $ICSRUrl, $pdfPath, $ecdcAgeGroup, $ecdcSexId) or die $sth->err();
			ecdc_notices();
		} else {
			my $ecdcNoticeId = $ecdcNotices{$noticeInternalId}->{'ecdcNoticeId'} // die;
			if ($ecdcNotices{$noticeInternalId}->{'ecdcSeriousness'} ne $ecdcSeriousness) {
				die "abnormal";
				my $sth = $dbh->prepare("UPDATE ecdc_notice SET ecdcSeriousness = $ecdcSeriousness WHERE id = $ecdcNoticeId");
				$sth->execute() or die $sth->err();
				# die "update to perform : " . $ecdcNotices{$noticeInternalId}->{'ecdcSeriousness'} . " ne $ecdcSeriousness";
			}
			if ($ecdcNotices{$noticeInternalId}->{'ecdcYearId'} ne $ecdcYearId) {
				my $sth = $dbh->prepare("UPDATE ecdc_notice SET ecdcYearId = $ecdcYearId WHERE id = $ecdcNoticeId");
				$sth->execute() or die $sth->err();
				# die "update to perform : " . $ecdcNotices{$noticeInternalId}->{'ecdcYearId'} . " ne $ecdcYearId";
			}
			if ($ecdcNotices{$noticeInternalId}->{'ecdcReporterType'} ne $ecdcReporterType) {
				my $sth = $dbh->prepare("UPDATE ecdc_notice SET ecdcReporterType = $ecdcReporterType WHERE id = $ecdcNoticeId");
				$sth->execute() or die $sth->err();
				# die "update to perform : " . $ecdcNotices{$noticeInternalId}->{'ecdcReporterType'} . " ne $ecdcReporterType";
			}
		}
		my $ecdcNoticeId = $ecdcNotices{$noticeInternalId}->{'ecdcNoticeId'} // die;

		# Inserting notice / drug relation if unknown.
		unless (exists $ecdcDrugNotices{$ecdcDrugId}->{$ecdcNoticeId}->{'ecdcDrugNoticeId'}) {
			my $sth = $dbh->prepare("INSERT INTO ecdc_drug_notice (ecdcDrugId, ecdcNoticeId) VALUES (?, ?)");
			$sth->execute($ecdcDrugId, $ecdcNoticeId) or die $sth->err();
			ecdc_drug_notices();
		}

		# Inserting reactions related to the notice ; if any valid one was parsed.
		for my $reaction (sort keys %noticeReactions) {
			my $outcome             = $noticeReactions{$reaction}->{'outcome'}             // die;
			my $seriousnessCriteria = $noticeReactions{$reaction}->{'seriousnessCriteria'} // die;
			unless (exists $ecdcReactions{$reaction}->{'ecdcReactionId'}) {
				my $sth = $dbh->prepare("INSERT INTO ecdc_reaction (name) VALUES (?)");
				$sth->execute($reaction) or die $sth->err();
				ecdc_reactions();
			}
			my $ecdcReactionId = $ecdcReactions{$reaction}->{'ecdcReactionId'} // die;
			unless (exists $ecdcReactionOutcomes{$outcome}->{'ecdcReactionOutcomeId'}) {
				my $sth = $dbh->prepare("INSERT INTO ecdc_reaction_outcome (name) VALUES (?)");
				$sth->execute($outcome) or die $sth->err();
				ecdc_reaction_outcomes();
			}
			my $ecdcReactionOutcomeId = $ecdcReactionOutcomes{$outcome}->{'ecdcReactionOutcomeId'} // die;
			unless (exists $ecdcReactionSeriousnesses{$seriousnessCriteria}->{'ecdcReactionSeriousnessId'}) {
				my $sth = $dbh->prepare("INSERT INTO ecdc_reaction_seriousness (name) VALUES (?)");
				$sth->execute($seriousnessCriteria) or die $sth->err();
				ecdc_reaction_seriousnesses();
			}
			my $ecdcReactionSeriousnessId = $ecdcReactionSeriousnesses{$seriousnessCriteria}->{'ecdcReactionSeriousnessId'} // die;
			# say "$ecdcReactionId | $reaction - $ecdcReactionOutcomeId | $outcome - $ecdcReactionSeriousnessId | $seriousnessCriteria";

			unless (exists $ecdcNoticeReactions{$ecdcNoticeId}->{$ecdcReactionId}->{'ecdcNoticeReactionId'}) {
				my $sth = $dbh->prepare("INSERT INTO ecdc_notice_reaction (ecdcNoticeId, ecdcReactionId, ecdcReactionSeriousnessId, ecdcReactionOutcomeId) VALUES ($ecdcNoticeId, $ecdcReactionId, $ecdcReactionSeriousnessId, $ecdcReactionOutcomeId)");
				$sth->execute() or die $sth->err();
				ecdc_notice_reactions();
			}
		}
		# say $_;
	}
	close $in;
	close $out;
	unlink $lineListingReportPath or die;
	say "";
	die if -f $lineListingReportPath;

	# Closing tab & returning to Line Listing.
	$driver->close;
	$driver->switch_to_window($handles->[0]);

	return $totalCases;
}

sub ecdc_reporter_type_to_enum {
	my ($ecdcReporterType) = @_;
	if ($ecdcReporterType eq 'Healthcare Professional') {
		$ecdcReporterType  = 1;
	} elsif ($ecdcReporterType eq 'Non Healthcare Professional') {
		$ecdcReporterType  = 2;
	} elsif ($ecdcReporterType eq 'Not Specified') {
		$ecdcReporterType  = 3;
	} else {
		die "ecdcReporterType : $ecdcReporterType";
	}
	return $ecdcReporterType;
}

sub ecdc_report_type_to_enum {
	my ($ecdcReportType) = @_;
	if ($ecdcReportType eq 'Spontaneous') {
		$ecdcReportType  = 1;
	} elsif ($ecdcReportType eq '') {
		$ecdcReportType  = 2;
	} else {
		die "ecdcReportType : $ecdcReportType";
	}
	return $ecdcReportType;
}

sub ecdc_geo_origin_to_enum {
	my ($ecdcGeographicalOrigin) = @_;
	if ($ecdcGeographicalOrigin eq 'European Economic Area') {
		$ecdcGeographicalOrigin  = 1;
	} elsif ($ecdcGeographicalOrigin eq 'Non European Economic Area') {
		$ecdcGeographicalOrigin  = 2;
	} elsif ($ecdcGeographicalOrigin eq 'Not Specified') {
		$ecdcGeographicalOrigin  = 3;
	} else {
		die "ecdcGeographicalOrigin : $ecdcGeographicalOrigin";
	}
	return $ecdcGeographicalOrigin;
}

sub browse_year_seriousness_age_group_by_sexes {
	say "browse_year_seriousness_age_group_by_sexes";
	my ($url, $ecdcDrugId, $ecdcDrugName, $aeFromEcdcYearId, $hasNullGateYear, $currentDrugs, $totalDrugs, $year, $ecdcYearId, $ecdcSeriousness, $ecdcSeriousnessLabel, $ageGroup, $ecdcAgeGroup) = @_;
	my $aeFromEcdcYear  = $ecdcYearsFromIds{$aeFromEcdcYearId}->{'name'} // die;

	# Refreshing product URL
	$driver->get($url);

	expect_line_listing();

	# Clicking Line Listing & Downloading every notice.
	select_line_listing();

	# Going through each incident sex group.
	my %sexGroups = list_sex_groups();
	# p %sexGroups;

	my $cumulatedTotal = 0;
	for my $sexGroup (sort keys %sexGroups) {
		my $currentDatetime = time::current_datetime();
		STDOUT->printflush("\r$currentDatetime - Getting [Drugs' Notices] - [$currentDrugs / $totalDrugs] - [$ecdcDrugName] - [$year] - [$ecdcSeriousnessLabel] - [$ageGroup] - [$sexGroup]                                             ");

		# Refreshing product URL
		$driver->get($url);

		expect_line_listing();

		# Clicking Line Listing & Downloading every notice.
		select_line_listing();

		# Selecting targeted year.
		list_years($url);
		sleep 2;
		select_year($year);
		sleep 2;

		# Selecting seriouness.
		select_serious_dropdown();
		sleep 2;
		select_dropdown_option($ecdcSeriousnessLabel);
		sleep 2;
		select_serious_dropdown();
		sleep 2;

		# Selecting age group.
		list_age_groups();
		sleep 2;
		select_dropdown_option($ageGroup);
		sleep 2;
		click_age_group();
		sleep 2;

		# Going through each incident sex group.
		list_sex_groups();
		sleep 2;
		my $ecdcSexGroup = sex_group_to_enum($sexGroup);
		# say "selecting sex group [$sexGroup]";
		select_dropdown_option($sexGroup);
		sleep 2;
		# say "closing sex group";
		click_sex_group();
		sleep 2;
		# say "running report";
		run_line_report();
		my $totalCases = parse_line_report($ecdcDrugId, $ecdcYearId, $ecdcSeriousness, $currentDrugs, $totalDrugs, $ecdcAgeGroup, $ecdcSexGroup);
		die unless defined $totalCases;
		if ($totalCases > 249000) {
			$totalCases = browse_year_seriousness_age_group_sex_by_geographical_origin($url, $ecdcDrugId, $ecdcDrugName, $aeFromEcdcYearId, $hasNullGateYear, $currentDrugs, $totalDrugs, $year, $ecdcYearId, $ecdcSeriousness, $ecdcSeriousnessLabel, $ageGroup, $ecdcAgeGroup, $sexGroup, $ecdcSexGroup);
		}
		$cumulatedTotal += $totalCases;
	}

	return $cumulatedTotal;
}

sub click_sex_group {
	# Locating Age Group button ID.
	my $content = $driver->get_page_source;
	my $tree    = HTML::Tree->new();
	$tree->parse($content);
	my @labels  = $tree->find('label');
	my ($selectId);
	for my $label (@labels) {
		next unless $label->attr_get_i('title');
		my $title = $label->attr_get_i('title');
		if ($title eq 'Sex') {
			my $for = $label->attr_get_i('for');
			# say "for      : $for";
			($selectId) = $for =~ /saw_(.*)_op/;
			# say "selectId : $selectId";
			last;
		}
	}

	# Selecting Gateway Date button.s
	my $sexGroupButton = $driver->find_element("(//img[\@id='saw_" . $selectId . "_1_dropdownIcon'])[1]");
	# say "clicking 1";
	$sexGroupButton->click();
	sleep 1;
}

sub list_sex_groups {

	click_sex_group();

	# Parsing years dropdown options.
	my %optionsIds = ();
	my $attempts   = 0;
	while (!keys %optionsIds) {
		my $div    = get_dropdown_div();
		my @divs   = $div->look_down(class=>"masterMenuItem promptMenuOption");
		for my $div (@divs) {
			my $label = $div->as_trimmed_text;
			$optionsIds{$label} = 1;
		}
		if (!keys %optionsIds) {
			sleep 1;
			$attempts++;
			say "More resilience to code here 5" if $attempts > 30;
			c_e() if $attempts > 30;
		}
	}

	sleep 1;
	return %optionsIds;
}

sub sex_group_to_enum {
	my ($sexGroup) = @_;
	my $ecdcSexGroup;
	if ($sexGroup eq 'Female') {
		$ecdcSexGroup = 1;
	} elsif ($sexGroup eq 'Male') {
		$ecdcSexGroup = 2;
	} elsif ($sexGroup eq 'Not Specified') {
		$ecdcSexGroup = 3;
	} else {
		die "ecdcSexGroup : [$ecdcSexGroup]";
	}
	return $ecdcSexGroup;
}

sub browse_year_seriousness_age_group_sex_by_geographical_origin {
	say "browse_year_seriousness_age_group_sex_by_geographical_origin";
	my (
		$url, $ecdcDrugId, $ecdcDrugName, $aeFromEcdcYearId, $hasNullGateYear,
		$currentDrugs, $totalDrugs, $year, $ecdcYearId, $ecdcSeriousness,
		$ecdcSeriousnessLabel, $ageGroup, $ecdcAgeGroup, $sexGroup, $ecdcSexGroup
	) = @_;

	my $aeFromEcdcYear  = $ecdcYearsFromIds{$aeFromEcdcYearId}->{'name'} // die;

	# Refreshing product URL
	$driver->get($url);

	expect_line_listing();

	# Clicking Line Listing & Downloading every notice.
	select_line_listing();

	# Going through each incident sex group.
	my %geoGroups = list_geo_origin_groups();
	# p %geoGroups;

	my $cumulatedTotal = 0;
	for my $geoGroup (sort keys %geoGroups) {
		my $currentDatetime = time::current_datetime();
		STDOUT->printflush("\r$currentDatetime - Getting [Drugs' Notices] - [$currentDrugs / $totalDrugs] - [$ecdcDrugName] - [$year] - [$ecdcSeriousnessLabel] - [$ageGroup] - [$sexGroup] - [$geoGroup]                                             ");

		# Refreshing product URL
		$driver->get($url);

		expect_line_listing();
		sleep 2;

		# Clicking Line Listing & Downloading every notice.
		select_line_listing();
		sleep 2;

		# Selecting targeted year.
		list_years($url);
		sleep 2;
		select_year($year);
		sleep 2;

		# Selecting seriouness.
		select_serious_dropdown();
		sleep 2;
		select_dropdown_option($ecdcSeriousnessLabel);
		sleep 2;
		select_serious_dropdown();
		sleep 2;

		# Selecting age group.
		list_age_groups();
		sleep 2;
		select_dropdown_option($ageGroup);
		sleep 2;
		click_age_group();

		# Selecting sex group.
		list_sex_groups();
		sleep 2;
		select_dropdown_option($sexGroup);
		sleep 2;
		click_sex_group();
		sleep 2;

		# Going through each incident geographical origin group.
		list_geo_origin_groups();
		sleep 2;
		my $ecdcGeoOriginGroup = geo_origin_group_to_enum($geoGroup);
		# say "selecting geo origin group [$geoGroup]";
		select_dropdown_option($geoGroup);
		sleep 2;
		# say "closing geo origin group";
		click_geo_origin_group();
		sleep 2;
		# say "running report";
		run_line_report();
		my $totalCases = parse_line_report($ecdcDrugId, $ecdcYearId, $ecdcSeriousness, $currentDrugs, $totalDrugs, $ecdcAgeGroup, $ecdcSexGroup, $ecdcGeoOriginGroup);
		die unless defined $totalCases;
		if ($totalCases > 249000) {
			$totalCases = browse_year_seriousness_age_group_sex_geographical_origin_by_reporter_type($url, $ecdcDrugId, $ecdcDrugName, $aeFromEcdcYearId, $hasNullGateYear, $currentDrugs, $totalDrugs, $year, $ecdcYearId, $ecdcSeriousness, $ecdcSeriousnessLabel, $ageGroup, $ecdcAgeGroup, $sexGroup, $ecdcSexGroup, $geoGroup, $ecdcGeoOriginGroup);
		}
		$cumulatedTotal += $totalCases;
	}
	return $cumulatedTotal;
}

sub click_geo_origin_group {
	# Locating Age Group button ID.
	my $content = $driver->get_page_source;
	my $tree    = HTML::Tree->new();
	$tree->parse($content);
	my @labels  = $tree->find('label');
	my ($selectId);
	for my $label (@labels) {
		next unless $label->attr_get_i('title');
		my $title = $label->attr_get_i('title');
		if ($title eq 'Geographic Origin') {
			my $for = $label->attr_get_i('for');
			# say "for      : $for";
			($selectId) = $for =~ /saw_(.*)_op/;
			# say "selectId : $selectId";
			last;
		}
	}

	# Selecting Gateway Date button.s
	my $geoOriginGroupButton = $driver->find_element("(//img[\@id='saw_" . $selectId . "_1_dropdownIcon'])[1]");
	# say "clicking 1";
	$geoOriginGroupButton->click();
	sleep 1;
}

sub list_geo_origin_groups {

	click_geo_origin_group();

	# Parsing years dropdown options.
	my %optionsIds = ();
	my $attempts   = 0;
	while (!keys %optionsIds) {
		my $div    = get_dropdown_div();
		my @divs   = $div->look_down(class=>"masterMenuItem promptMenuOption");
		for my $div (@divs) {
			my $label = $div->as_trimmed_text;
			$optionsIds{$label} = 1;
		}
		if (!keys %optionsIds) {
			sleep 1;
			$attempts++;
			say "More resilience to code here 1" if $attempts > 30;
			c_e() if $attempts > 30;
		}
	}

	sleep 1;
	return %optionsIds;
}

sub geo_origin_group_to_enum {
	my ($geoOriginGroup) = @_;
	my $ecdcGeoOriginGroup;
	if ($geoOriginGroup eq 'European Economic Area') {
		$ecdcGeoOriginGroup = 1;
	} elsif ($geoOriginGroup eq 'Non European Economic Area') {
		$ecdcGeoOriginGroup = 2;
	} elsif ($geoOriginGroup eq 'Not Specified') {
		$ecdcGeoOriginGroup = 3;
	} else {
		die "ecdcGeoOriginGroup : [$ecdcGeoOriginGroup]";
	}
	return $ecdcGeoOriginGroup;
}

sub browse_year_seriousness_age_group_sex_geographical_origin_by_reporter_type {
	say "browse_year_seriousness_age_group_sex_geographical_origin_by_reporter_type";
	my (
		$url, $ecdcDrugId, $ecdcDrugName, $aeFromEcdcYearId, $hasNullGateYear,
		$currentDrugs, $totalDrugs, $year, $ecdcYearId, $ecdcSeriousness,
		$ecdcSeriousnessLabel, $ageGroup, $ecdcAgeGroup, $sexGroup, $ecdcSexGroup,
		$geoGroup, $ecdcGeoOriginGroup
	) = @_;

	my $aeFromEcdcYear  = $ecdcYearsFromIds{$aeFromEcdcYearId}->{'name'} // die;

	# Refreshing product URL
	$driver->get($url);

	expect_line_listing();

	# Clicking Line Listing & Downloading every notice.
	select_line_listing();

	# Going through each incident sex group.
	my %reporterTypeGroups = list_reporter_type_groups();
	# p %reporterTypeGroups;

	my $cumulatedTotal = 0;
	for my $reporterType (sort keys %reporterTypeGroups) {
		my $currentDatetime = time::current_datetime();
		STDOUT->printflush("\r$currentDatetime - Getting [Drugs' Notices] - [$currentDrugs / $totalDrugs] - [$ecdcDrugName] - [$year] - [$ecdcSeriousnessLabel] - [$ageGroup] - [$sexGroup] - [$geoGroup] - [$reporterType]                                             ");

		# Refreshing product URL
		$driver->get($url);

		expect_line_listing();

		# Clicking Line Listing & Downloading every notice.
		sleep 2;
		select_line_listing();

		# Selecting targeted year.
		list_years($url);
		sleep 2;
		select_year($year);
		sleep 2;

		# Selecting seriouness.
		select_serious_dropdown();
		sleep 2;
		select_dropdown_option($ecdcSeriousnessLabel);
		sleep 2;
		select_serious_dropdown();

		# Selecting age group.
		list_age_groups();
		sleep 2;
		select_dropdown_option($ageGroup);
		sleep 2;
		click_age_group();

		# Selecting sex group.
		list_sex_groups();
		sleep 2;
		select_dropdown_option($sexGroup);
		sleep 2;
		click_sex_group();
		sleep 2;

		# Selecting geo origin group.
		list_geo_origin_groups();
		sleep 2;
		select_dropdown_option($geoGroup);
		sleep 2;
		click_geo_origin_group();
		sleep 2;

		# Going through each incident geographical origin group.
		list_reporter_type_groups();
		my $ecdcReporterTypeGroup = ecdc_reporter_type_to_enum($reporterType);
		# say "selecting reporter type group [$reporterType]";
		select_dropdown_option($reporterType);
		sleep 2;
		# say "closing reporter type group";
		click_reporter_type_group();
		sleep 2;
		# say "running report";
		run_line_report();
		my $totalCases = parse_line_report($ecdcDrugId, $ecdcYearId, $ecdcSeriousness, $currentDrugs, $totalDrugs, $ecdcAgeGroup, $ecdcSexGroup, $ecdcGeoOriginGroup, $ecdcReporterTypeGroup);
		die unless defined $totalCases;
		if ($totalCases > 249000) {
			die;
		}
		$cumulatedTotal += $totalCases;

	}
	return $cumulatedTotal;
}

sub click_reporter_type_group {
	# Locating Age Group button ID.
	my $content = $driver->get_page_source;
	my $tree    = HTML::Tree->new();
	$tree->parse($content);
	my @labels  = $tree->find('label');
	my ($selectId);
	for my $label (@labels) {
		next unless $label->attr_get_i('title');
		my $title = $label->attr_get_i('title');
		if ($title eq 'Reporter Group') {
			my $for = $label->attr_get_i('for');
			# say "for      : $for";
			($selectId) = $for =~ /saw_(.*)_op/;
			# say "selectId : $selectId";
			last;
		}
	}

	# Selecting Gateway Date button.s
	my $geoOriginGroupButton = $driver->find_element("(//img[\@id='saw_" . $selectId . "_1_dropdownIcon'])[1]");
	# say "clicking 1";
	$geoOriginGroupButton->click();
	sleep 1;
}

sub list_reporter_type_groups {

	click_reporter_type_group();

	# Parsing years dropdown options.
	my %optionsIds = ();
	my $attempts   = 0;
	while (!keys %optionsIds) {
		my $div    = get_dropdown_div();
		my @divs   = $div->look_down(class=>"masterMenuItem promptMenuOption");
		for my $div (@divs) {
			my $label = $div->as_trimmed_text;
			$optionsIds{$label} = 1;
		}
		if (!keys %optionsIds) {
			sleep 1;
			$attempts++;
			say "More resilience to code here 3" if $attempts > 30;
			c_e() if $attempts > 30;
		}
	}

	sleep 1;
	return %optionsIds;
}