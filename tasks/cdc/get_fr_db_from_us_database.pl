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

# Profile Path Configuration.
my $sourceId                = 2;    # DB hard-coded corresponding value.
my $limitsToBulkDL          = 1000; # Above this number of reports to DL, we distribute to totalThreadsOnBulkDL threads.
my $totalThreadsOnBulkDL    = 12;   # Total Threads On Bulk Download.
my $chromeProfileNum        = 2;    # Profile 1 is attributed to EU's scrapper.
my $dataDir                 = "C:\\Users\\Utilisateur\\AppData\\Local\\Google\\Chrome\\User Data";
my $profileDir              = "Profile $chromeProfileNum";
my $fullPath                = "$dataDir\\$profileDir";

# Using chromeOptions to start chrome.
my $capabilities            = {};
$capabilities->{"goog:chromeOptions"} = {
	"args" => [
		"user-data-dir=$fullPath",
		"profile-directory=$profileDir"
	]
};
my $driver                  = Selenium::Chrome->new('extra_capabilities' => $capabilities);
my $baseUrl                 = "https://wonder.cdc.gov/vaers.html";

# Fetching data which already has been indexed.
my $latestCdcStateId        = 0;
my %cdcStates               = ();
cdc_states();
my $latestCdcAgeId          = 0;
my %cdcAges                 = ();
cdc_ages();
my $latestCdcSexeId         = 0;
my %cdcSexes                = ();
cdc_sexes();
my $latestCdcStateYearId    = 0;
my %cdcStateYears           = ();
cdc_state_years();
my $latestCdcManufacturerId = 0;
my %cdcManufacturers        = ();
cdc_manufacturers();
my $latestCdcDoseId = 0;
my %cdcDoses        = ();
cdc_doses();
my $latestCdcReportId       = 0;
my %cdcReports              = ();
cdc_reports();

# Getting list of foreign reports & their Imm Reference, if an update is required (no update has been fully performed on current day).
my $indexUpdateTimestamp    = get_current_index_update();
my $currentTimestamp        = time::current_timestamp();
if (!$indexUpdateTimestamp || ($indexUpdateTimestamp && ($indexUpdateTimestamp + 86400) < $currentTimestamp)) {
	search_reports_by_states();
}

# Fetching reports data.
# get_reports_data();

sub cdc_states {
	my $tb = $dbh->selectall_hashref("SELECT id as cdcStateId, internalId, name FROM cdc_state WHERE id > $latestCdcStateId", 'cdcStateId');
	for my $cdcStateId (sort{$a <=> $b} keys %$tb) {
		$latestCdcStateId = $cdcStateId;
		my $internalId    = %$tb{$cdcStateId}->{'internalId'} // die;
		my $name          = %$tb{$cdcStateId}->{'name'}       // die;
		$cdcStates{$internalId}->{'cdcStateId'} = $cdcStateId;
		$cdcStates{$internalId}->{'name'} = $name;
	}
}

sub cdc_ages {
	my $tb = $dbh->selectall_hashref("SELECT id as cdcAgeId, internalId, name FROM cdc_age WHERE id > $latestCdcAgeId", 'cdcAgeId');
	for my $cdcAgeId (sort{$a <=> $b} keys %$tb) {
		$latestCdcAgeId = $cdcAgeId;
		my $internalId  = %$tb{$cdcAgeId}->{'internalId'} // die;
		my $name        = %$tb{$cdcAgeId}->{'name'}       // die;
		$cdcAges{$internalId}->{'cdcAgeId'} = $cdcAgeId;
		$cdcAges{$internalId}->{'name'} = $name;
	}
}

sub cdc_sexes {
	my $tb = $dbh->selectall_hashref("SELECT id as cdcSexeId, internalId, name FROM cdc_sexe WHERE id > $latestCdcSexeId", 'cdcSexeId');
	for my $cdcSexeId (sort{$a <=> $b} keys %$tb) {
		$latestCdcSexeId = $cdcSexeId;
		my $internalId  = %$tb{$cdcSexeId}->{'internalId'} // die;
		my $name        = %$tb{$cdcSexeId}->{'name'}       // die;
		$cdcSexes{$internalId}->{'cdcSexeId'} = $cdcSexeId;
		$cdcSexes{$internalId}->{'name'} = $name;
	}
}

sub cdc_manufacturers {
	my $tb = $dbh->selectall_hashref("SELECT id as cdcManufacturerId, internalId, name FROM cdc_manufacturer WHERE id > $latestCdcManufacturerId", 'cdcManufacturerId');
	for my $cdcManufacturerId (sort{$a <=> $b} keys %$tb) {
		$latestCdcManufacturerId = $cdcManufacturerId;
		my $internalId  = %$tb{$cdcManufacturerId}->{'internalId'} // die;
		my $name  = %$tb{$cdcManufacturerId}->{'name'} // die;
		$cdcManufacturers{$internalId}->{'cdcManufacturerId'} = $cdcManufacturerId;
		$cdcManufacturers{$internalId}->{'name'} = $name;
	}
}

sub cdc_doses {
	my $tb = $dbh->selectall_hashref("SELECT id as cdcDoseId, internalId, name FROM cdc_dose WHERE id > $latestCdcDoseId", 'cdcDoseId');
	for my $cdcDoseId (sort{$a <=> $b} keys %$tb) {
		$latestCdcDoseId = $cdcDoseId;
		my $internalId  = %$tb{$cdcDoseId}->{'internalId'} // die;
		my $name  = %$tb{$cdcDoseId}->{'name'} // die;
		$cdcDoses{$internalId}->{'cdcDoseId'} = $cdcDoseId;
		$cdcDoses{$internalId}->{'name'} = $name;
	}
}

sub cdc_reports {
	my $tb = $dbh->selectall_hashref("SELECT id as cdcReportId, internalId, detailsTimestamp FROM cdc_report WHERE id > $latestCdcReportId", 'cdcReportId');
	for my $cdcReportId (sort{$a <=> $b} keys %$tb) {
		$latestCdcReportId   = $cdcReportId;
		my $internalId       = %$tb{$cdcReportId}->{'internalId'} // die;
		my $detailsTimestamp = %$tb{$cdcReportId}->{'detailsTimestamp'};
		$cdcReports{$internalId}->{'cdcReportId'}      = $cdcReportId;
		$cdcReports{$internalId}->{'detailsTimestamp'} = $detailsTimestamp if $detailsTimestamp;
	}
}

sub cdc_state_years {
	my $tb = $dbh->selectall_hashref("SELECT id as cdcStateYearId, cdcStateId, year, totalReports FROM cdc_state_year WHERE id > $latestCdcStateYearId", 'cdcStateYearId');
	for my $cdcStateYearId (sort{$a <=> $b} keys %$tb) {
		$latestCdcStateYearId = $cdcStateYearId;
		my $cdcStateId   = %$tb{$cdcStateYearId}->{'cdcStateId'}   // die;
		my $year         = %$tb{$cdcStateYearId}->{'year'}         // die;
		my $totalReports = %$tb{$cdcStateYearId}->{'totalReports'} // die;
		$cdcStateYears{$cdcStateId}->{$year}->{'cdcStateYearId'} = $cdcStateYearId;
		$cdcStateYears{$cdcStateId}->{$year}->{'totalReports'}   = $totalReports;
	}
}

sub get_current_index_update {
	my $tb = $dbh->selectrow_hashref("SELECT indexUpdateTimestamp FROM source WHERE id = $sourceId", undef);
	return %$tb{'indexUpdateTimestamp'};
}

sub search_reports_by_states {
	my $currentDatetime = time::current_datetime();
	say "$currentDatetime - Getting [$baseUrl] ...";
	$driver->get($baseUrl);
    $currentDatetime = time::current_datetime();
    say "$currentDatetime - Verifying disclaimer ...";
	cdc::verify_disclaimer($driver);
	select_search();
	select_report_vaers_id();
	select_report_reference();
	unselect_all_states();

	# Listing states, ages, sexes & manufacturers filters.
	list_all_states();
	list_all_ages();
	list_all_sexes();
	list_all_manufacturers();
	list_all_doses();

	# For each state, reviewing reports ; and refining further by year since 1980, age, and sexe if required.
	my $formerState;
	my $totalStates  = keys %cdcStates;
	my $currentState = 0;
	for my $cdcStateInternalId (sort keys %cdcStates) {
		$currentState++;
		if ($formerState) {
			my $currentDatetime = time::current_datetime();
			say "$currentDatetime - Resetting form ...";
			reset_form();
			select_report_vaers_id();
			select_report_reference();
			unselect_all_states();
		}
		$formerState        = $cdcStateInternalId;
		my $cdcStateId      = $cdcStates{$cdcStateInternalId}->{'cdcStateId'} // die;
		my $cdcStateName    = $cdcStates{$cdcStateInternalId}->{'name'}       // die;
		my $currentDatetime = time::current_datetime();
		say "$currentDatetime - Clicking option field on search [state] - [$cdcStateName] - [$currentState / $totalStates] ...";
		select_state($cdcStateInternalId);
		# $optionFieldState->set_selected();

		# Casting form & verifying number of results.
		cast_form();
		my ($hasResults, $requiresFiltering) = verify_form_results();

		# If no result has been rendered, additionally filtering by year.
		unless ($hasResults == 1) {
			die unless $requiresFiltering;

			# For each vaccination year, browsing reports.
			unselect_all_dates();
			my $formerYear;
			for my $year (1980 .. 2022) {

				# Ensures years post 2016 are updated on every iteration.
				if (exists $cdcStateYears{$cdcStateId}->{$year}) {
				# if ($year < 2020 && exists $cdcStateYears{$cdcStateId}->{$year}) {
					next;
				}

				# If a year already has been selected, unselecting it.
				if (defined $formerYear) {
					my $currentDatetime = time::current_datetime();
					say "$currentDatetime - Unselecting former option field on search [vaccination date] - [$formerYear] ...";
					select_year($formerYear);
				}
				$formerYear = $year;

				# Selecting targeted year.
				my $currentDatetime = time::current_datetime();
				say "$currentDatetime - Clicking option field on search [vaccination date] - [$year] ...";
				select_year($year);

				# Casting form & verifying number of results.
				cast_form();
				my ($hasResults, $requiresFiltering) = verify_form_results();

				# If no result has been rendered, additionally filtering by age.
				my $totalReports = 0;
				unless ($hasResults == 1) {
					die unless $requiresFiltering;
					unselect_all_ages();
					sleep 1;
					my $formerAge;
					for my $cdcAgeInternalId (sort keys %cdcAges) {
						if (defined $formerAge) {
							my $cdcAgeName = $cdcAges{$formerAge}->{'name'} // die;
							my $currentDatetime = time::current_datetime();
							say "$currentDatetime - Unselecting former option field on search [age] - [$cdcAgeName] ...";
							select_age($formerAge);
						}
						$formerAge     = $cdcAgeInternalId;
						my $cdcAgeName = $cdcAges{$cdcAgeInternalId}->{'name'} // die;
						# say "cdcAgeInternalId : $cdcAgeInternalId";
						# say "cdcAgeName       : $cdcAgeName";
						my $currentDatetime = time::current_datetime();
						say "$currentDatetime - Clicking option field on search [age] - [$cdcAgeName] ...";
						select_age($cdcAgeInternalId);
						cast_form();
						my ($hasResults, $requiresFiltering) = verify_form_results();

						# If no result has been rendered, additionally filtering by sexe.
						unless ($hasResults) {
							die unless $requiresFiltering;
							unselect_all_sexes();
							my $formerSexe;
							for my $cdcSexeInternalId (sort keys %cdcSexes) {
								if (defined $formerSexe) {
									my $cdcSexeName = $cdcSexes{$formerSexe}->{'name'} // die;
									my $currentDatetime = time::current_datetime();
									say "$currentDatetime - Unselecting former option field on search [sexe] - [$cdcSexeName] ...";
									select_sexe($formerSexe);
								}
								$formerSexe = $cdcSexeInternalId;
								my $cdcSexeName = $cdcSexes{$cdcSexeInternalId}->{'name'} // die;
								# say "cdcSexeInternalId : $cdcSexeInternalId";
								# say "cdcSexeName       : $cdcSexeName";
								my $currentDatetime = time::current_datetime();
								say "$currentDatetime - Clicking option field on search [sexe] - [$cdcSexeName] ...";
								select_sexe($cdcSexeInternalId);
								cast_form();
								my ($hasResults, $requiresFiltering) = verify_form_results();

								# If no result has been rendered, additionally filtering by manufacturer.
								unless ($hasResults) {
									die unless $requiresFiltering;
									unselect_all_manufacturers();
									my $formerManufacturer;
									for my $cdcManufacturerInternalId (sort keys %cdcManufacturers) {
										if (defined $formerManufacturer) {
											my $cdcManufacturerName = $cdcManufacturers{$formerManufacturer}->{'name'} // die;
											my $currentDatetime = time::current_datetime();
											say "$currentDatetime - Unselecting former option field on search [manufacturer] - [$cdcManufacturerName] ...";
											select_manufacturer($formerManufacturer);
										}
										$formerManufacturer = $cdcManufacturerInternalId;
										my $cdcManufacturerName = $cdcManufacturers{$cdcManufacturerInternalId}->{'name'} // die;
										# say "cdcManufacturerInternalId : $cdcManufacturerInternalId";
										# say "cdcManufacturerName       : $cdcManufacturerName";
										my $currentDatetime = time::current_datetime();
										say "$currentDatetime - Clicking option field on search [manufacturer] - [$cdcManufacturerName] ...";
										select_manufacturer($cdcManufacturerInternalId);
										cast_form();
										my ($hasResults, $requiresFiltering) = verify_form_results();

										# If no result has been rendered, additionally filtering by dose.
										unless ($hasResults) {
											die unless $requiresFiltering;
											unselect_all_doses();
											my $formerDose;
											for my $cdcDoseInternalId (sort keys %cdcDoses) {
												if (defined $formerDose) {
													my $cdcDoseName = $cdcDoses{$formerDose}->{'name'} // die;
													my $currentDatetime = time::current_datetime();
													say "$currentDatetime - Unselecting former option field on search [dose] - [$cdcDoseName] ...";
													select_dose($formerDose);
												}
												$formerDose = $cdcDoseInternalId;
												my $cdcDoseName = $cdcDoses{$cdcDoseInternalId}->{'name'} // die;
												# say "cdcDoseInternalId : $cdcDoseInternalId";
												# say "cdcDoseName       : $cdcDoseName";
												my $currentDatetime = time::current_datetime();
												say "$currentDatetime - Clicking option field on search [dose] - [$cdcDoseName] ...";
												select_dose($cdcDoseInternalId);
												cast_form();
												my ($hasResults, $requiresFiltering) = verify_form_results();
												die unless ($hasResults);
												$totalReports += parse_vaers_reports($cdcStateInternalId);
												return_to_form();
											}
										} else {
											$totalReports += parse_vaers_reports($cdcStateInternalId);
										}
										return_to_form();
									}
								} else {
									$totalReports += parse_vaers_reports($cdcStateInternalId);
								}
								return_to_form();
							}

							# Returns to form.
							return_to_form();
						} else {
							$totalReports += parse_vaers_reports($cdcStateInternalId);
						}

						# Returns to form.
						return_to_form();
					}
				} else {
					$totalReports += parse_vaers_reports($cdcStateInternalId);
				}
				# say "$year : $totalReports";

				# Returns to form.
				return_to_form();


				# Inserts or updates total report on year / state in order to speed up further updates.
				unless (exists $cdcStateYears{$cdcStateId}->{$year}->{'cdcStateYearId'}) {
					my $sth = $dbh->prepare("INSERT INTO cdc_state_year (cdcStateId, year, totalReports, updateTimestamp) VALUES (?, ?, ?, UNIX_TIMESTAMP())");
					$sth->execute($cdcStateId, $year, $totalReports) or die $sth->err();
					cdc_state_years();
				} else {
					my $cdcStateYearId = $cdcStateYears{$cdcStateId}->{$year}->{'cdcStateYearId'} // die;
					if ($cdcStateYears{$cdcStateId}->{$year}->{'totalReports'} != $totalReports) {
						my $sth = $dbh->prepare("UPDATE cdc_state_year SET totalReports = ?, updateTimestamp = UNIX_TIMESTAMP() WHERE cdcStateId = $cdcStateId AND year = $year");
						$sth->execute($totalReports) or die $sth->err();
						$cdcStateYears{$cdcStateId}->{$year}->{'totalReports'} = $totalReports;
					}
				}
			}
		} else {
			parse_vaers_reports($cdcStateInternalId);
		}

		# Returns to form.
		return_to_form();
	}

	# If everything went fine so far, setting indexation timestamp.
	my $uts = time::current_timestamp();
	my $sth = $dbh->prepare("UPDATE source SET indexUpdateTimestamp = $uts WHERE id = $sourceId");
	$sth->execute() or die $sth->err();
}

sub select_report_vaers_id {
	my $currentDatetime = time::current_datetime();
	say "$currentDatetime - Clicking on search [field displayed] ...";
	my $searchField = $driver->find_element("(//select[\@id='SB_1'])[1]");
	$searchField->click();
	$currentDatetime = time::current_datetime();
	say "$currentDatetime - Clicking option field on search [field displayed] ...";
	my $optionField = $driver->find_element("(//option[\@value='D8.V15'])[1]");
	$optionField->click();
	$currentDatetime = time::current_datetime();
	say "$currentDatetime - Closing search [field displayed] ...";
	$searchField->click();
}

sub select_report_reference {
	my $currentDatetime = time::current_datetime();
	say "$currentDatetime - Clicking on search [field displayed 2] ...";
	my $searchField = $driver->find_element("(//select[\@id='SB_2'])[1]");
	$searchField->click();
	my $content = $driver->get_page_source;
	my $tree    = HTML::Tree->new();
	$tree->parse($content);
	# open my $out, '>:utf8', 'cdctree.html';
	# say $out $tree->as_HTML('<>&', "\t");
	# close $out;
	# exit;
	$currentDatetime = time::current_datetime();
	say "$currentDatetime - Clicking option field on search [field displayed 2] ...";
	my $optionField = $driver->find_element("(//option[\@value='D8.V22'])[2]");
	$optionField->click();
	$currentDatetime = time::current_datetime();
	say "$currentDatetime - Closing search [field displayed 2] ...";
	$searchField->click();
}

sub unselect_all_dates {
	my $optionFieldDate = $driver->find_element("(//select[\@id='codes-D8.V3']/option[\@value='*All*'])[1]");
	$optionFieldDate->click();
}

sub unselect_all_states {
	my $optionFieldState = $driver->find_element("(//select[\@id='SD8.V12']/option[\@value='00'])[1]");
	$optionFieldState->click();
}

sub unselect_all_ages {
	my $optionFieldAge = $driver->find_element("(//select[\@id='SD8.V1']/option[\@value='*All*'])[1]");
	$optionFieldAge->click();
}

sub unselect_all_sexes {
	my $optionFieldSexe = $driver->find_element("(//select[\@id='SD8.V5']/option[\@value='*All*'])[1]");
	$optionFieldSexe->click();
}

sub unselect_all_manufacturers {
	my $optionFieldSexe = $driver->find_element("(//select[\@id='SD8.V6']/option[\@value='*All*'])[1]");
	$optionFieldSexe->click();
}

sub unselect_all_doses {
	my $optionFieldSexe = $driver->find_element("(//select[\@id='SD8.V25']/option[\@value='*All*'])[1]");
	$optionFieldSexe->click();
}

sub list_all_states {
	my $content = $driver->get_page_source;
	my $tree    = HTML::Tree->new();
	$tree->parse($content);
	# open my $out, '>', 'tmp.html';
	# say $out $tree->as_HTML('<>&', "\t");
	# close $out;
	my $stateSelector = $tree->look_down(id=>"SD8.V12");
	my @states = $stateSelector->find('option');
	for my $stateOption (@states) {
		my $value = $stateOption->attr_get_i('value') // die;
		my $state = $stateOption->as_trimmed_text;
		$state    =~ s/ //g;
		next unless
			$state eq 'Foreign';
		# say "$state - $value";
		unless (exists $cdcStates{$value}->{'cdcStateId'}) {
			my $sth = $dbh->prepare("INSERT INTO cdc_state (internalId, name) VALUES (?, ?)");
			$sth->execute($value, $state) or die $sth->err();
			cdc_states();
		}

	}
}

sub list_all_ages {
	my $content = $driver->get_page_source;
	my $tree    = HTML::Tree->new();
	$tree->parse($content);
	my $ageSelector = $tree->look_down(id=>"SD8.V1");
	my @ages = $ageSelector->find('option');
	for my $ageOption (@ages) {
		my $value = $ageOption->attr_get_i('value') // die;
		my $age = $ageOption->as_trimmed_text;
		$age    =~ s/ //g;
		next if
			$age eq 'All Ages';
		# say "$age - $value";
		unless (exists $cdcAges{$value}->{'cdcAgeId'}) {
			my $sth = $dbh->prepare("INSERT INTO cdc_age (internalId, name) VALUES (?, ?)");
			$sth->execute($value, $age) or die $sth->err();
			cdc_ages();
		}
	}
}

sub list_all_sexes {
	my $content = $driver->get_page_source;
	my $tree    = HTML::Tree->new();
	$tree->parse($content);
	my $sexeSelector = $tree->look_down(id=>"SD8.V5");
	my @sexes = $sexeSelector->find('option');
	for my $sexeOption (@sexes) {
		my $value = $sexeOption->attr_get_i('value') // die;
		my $sexe = $sexeOption->as_trimmed_text;
		$sexe    =~ s/ //g;
		next if
			$sexe eq 'All Genders';
		# say "$sexe - $value";
		unless (exists $cdcStates{$value}->{'cdcStateId'}) {
			my $sth = $dbh->prepare("INSERT INTO cdc_sexe (internalId, name) VALUES (?, ?)");
			$sth->execute($value, $sexe) or die $sth->err();
			cdc_sexes();
		}
	}
}

sub list_all_manufacturers {
	my $content = $driver->get_page_source;
	my $tree    = HTML::Tree->new();
	$tree->parse($content);
	my $manufacturerSelector = $tree->look_down(id=>"SD8.V6");
	my @manufacturers = $manufacturerSelector->find('option');
	for my $manufacturerOption (@manufacturers) {
		my $value = $manufacturerOption->attr_get_i('value') // die;
		my $manufacturer = $manufacturerOption->as_trimmed_text;
		$manufacturer    =~ s/ //g;
		next if
			$manufacturer eq 'All Manufacturers';
		# say "$manufacturer - $value";
		unless (exists $cdcManufacturers{$value}->{'cdcManufacturerId'}) {
			my $sth = $dbh->prepare("INSERT INTO cdc_manufacturer (internalId, name) VALUES (?, ?)");
			$sth->execute($value, $manufacturer) or die $sth->err();
			cdc_manufacturers();
		}
	}
}

sub list_all_doses {
	my $content = $driver->get_page_source;
	my $tree    = HTML::Tree->new();
	$tree->parse($content);
	my $doseSelector = $tree->look_down(id=>"SD8.V25");
	my @doses = $doseSelector->find('option');
	for my $doseOption (@doses) {
		my $value = $doseOption->attr_get_i('value') // die;
		my $dose = $doseOption->as_trimmed_text;
		$dose    =~ s/ //g;
		next if
			$dose eq 'All Doses';
		# say "$dose - $value";
		unless (exists $cdcDoses{$value}->{'cdcDoseId'}) {
			my $sth = $dbh->prepare("INSERT INTO cdc_dose (internalId, name) VALUES (?, ?)");
			$sth->execute($value, $dose) or die $sth->err();
			cdc_doses();
		}
	}
}

sub cast_form {
	my $submitButton = $driver->find_element("(//input[\@id='submit-button1'])[1]");
	$submitButton->click();
	sleep 1;
}

sub parse_vaers_reports {
	my ($cdcStateInternalId) = @_;
	my $cdcStateId   = $cdcStates{$cdcStateInternalId}->{'cdcStateId'} // die;
	my $content      = $driver->get_page_source;
	my $tree         = HTML::Tree->new();
	$tree->parse($content);
	# open my $out, '>:utf8', 'cdctree.html';
	# say $out $tree->as_HTML('<>&', "\t");
	# close $out;
	# exit;
	my $responseForm = $tree->look_down(class=>"response-form");
	my @vaersReports = $responseForm->find('tr');
	my $parsed = 0;
	for my $varsReportData (@vaersReports) {
		next unless $varsReportData->find('th');
		my @ths = $varsReportData->find('th');
		my $immProjectNumber = $ths[1]->as_trimmed_text;
		next unless $varsReportData->find('input');
		$varsReportData = $varsReportData->find('input');
		my $varsReport  = $varsReportData->attr_get_i('value');
		unless (exists $cdcReports{$varsReport}->{'cdcReportId'}) {
			my $sth = $dbh->prepare("INSERT INTO cdc_report (cdcStateId, internalId, immProjectNumber) VALUES ($cdcStateId, ?, ?)");
			$sth->execute($varsReport, $immProjectNumber) or die $sth->err();
			cdc_reports();
		}
		my $cdcReportId = $cdcReports{$varsReport}->{'cdcReportId'} // die;
		$parsed++;
		# say "varsReport       : $varsReport";
		# say "immProjectNumber : $immProjectNumber";
		# say "cdcReportId      : $cdcReportId";
	}
	# open my $out, '>', 'tmp.html';
	# say $out $tree->as_HTML('<>&', "\t");
	# close $out;
	return $parsed;
}

sub return_to_form {
	my $formButton = $driver->find_element("(//input[\@value='Request Form'])[1]");
	$formButton->click();
	sleep 2;
}

sub select_search {
	my $accessSearch = $driver->find_element("(//input[\@value='VAERS Data Search'])[2]");
	$accessSearch->click();
	sleep 2;
}

sub select_state {
	my ($cdcStateInternalId) = @_;
	my $optionFieldState = $driver->find_element("(//select[\@id='SD8.V12']/option[\@value='" . $cdcStateInternalId . "'])[1]");
	$optionFieldState->click();
}

sub select_year {
	my ($year) = @_;
	my $optionFieldVaccinatedYear = $driver->find_element("(//select[\@id='codes-D8.V3']/option[\@value='". $year . "'])[1]");
	$optionFieldVaccinatedYear->click();
}

sub select_age {
	my ($cdcAgeInternalId) = @_;
	my $optionFieldAge = $driver->find_element("(//select[\@id='SD8.V1']/option[\@value='". $cdcAgeInternalId . "'])[1]");
	$optionFieldAge->click();
}

sub select_sexe {
	my ($cdcSexeInternalId) = @_;
	my $optionFieldSexe = $driver->find_element("(//select[\@id='SD8.V5']/option[\@value='". $cdcSexeInternalId . "'])[1]");
	$optionFieldSexe->click();
}

sub select_manufacturer {
	my ($cdcManufacturerInternalId) = @_;
	my $optionFieldManufacturer = $driver->find_element("(//select[\@id='SD8.V6']/option[\@value='". $cdcManufacturerInternalId . "'])[1]");
	$optionFieldManufacturer->click();
}

sub select_dose {
	my ($cdcDoseInternalId) = @_;
	my $optionFieldDose = $driver->find_element("(//select[\@id='SD8.V25']/option[\@value='". $cdcDoseInternalId . "'])[1]");
	$optionFieldDose->click();
}

sub reset_form {
	my $accessSearch = $driver->find_element("(//input[\@value='Reset'])[1]");
	$accessSearch->click();
	sleep 2;
}

sub verify_form_results {

	# Verifying if results have been rendered.
	my $content           = $driver->get_page_source;
	my $tree              = HTML::Tree->new();
	$tree->parse($content);
	my $hasResults        = 0;
	my $requiresFiltering = 0;
	my @errorMessages     = $tree->look_down(class=>"error-message");
	for my $errorMessage (@errorMessages) {
		my $text   = $errorMessage->as_trimmed_text;
		$text      =~ s/  //;
		if ($text  =~ /These results are for .* total events\./) {
			$hasResults = 1;
			last;
		} elsif ($text =~ /This request produces .* rows, but 10,000 is the maximum allowed\./) {
			$requiresFiltering = 1;
			last;
		}
		# say "text : $text";
	}
	return ($hasResults, $requiresFiltering);
}

sub get_reports_data {
	my $currentDatetime = time::current_datetime();
	say "$currentDatetime - Getting [$baseUrl] ...";
	$driver->get($baseUrl);
	cdc::verify_disclaimer($driver);
	cdc::select_event_details($driver);
	my $currentReport = 0;
	my $totalReports  = 0;
	for my $cdcReportInternalId (sort keys %cdcReports) {
		my $cdcReportId = $cdcReports{$cdcReportInternalId}->{'cdcReportId'} // die;
		next if exists $cdcReports{$cdcReportInternalId}->{'detailsTimestamp'};
		$totalReports++;
	}
	if ($totalReports < $limitsToBulkDL) {
		for my $cdcReportInternalId (sort keys %cdcReports) {
			# next unless $cdcReportInternalId eq '0059272-1';
			my $cdcReportId = $cdcReports{$cdcReportInternalId}->{'cdcReportId'} // die;
			# say "cdcReportId         : $cdcReportId";
			# say "cdcReportInternalId : $cdcReportInternalId";
			next if exists $cdcReports{$cdcReportInternalId}->{'detailsTimestamp'};
			my $currentDatetime = time::current_datetime();
			$currentReport++;
			STDOUT->printflush("\r$currentDatetime - Fetching report data - [$cdcReportInternalId] - [$currentReport / $totalReports] ...");

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
		say "" if $totalReports;
		$driver->shutdown_binary;
	} else {
		use Proc::Background;
		my $currentDatetime = time::current_datetime();
		say "$currentDatetime - Splitting & distributing the volume of [$totalReports] reports to [$totalThreadsOnBulkDL] sub-threads.";
		$driver->shutdown_binary;
		my %reportsByIds  = ();
		for my $cdcReportInternalId (sort keys %cdcReports) {
			my $cdcReportId = $cdcReports{$cdcReportInternalId}->{'cdcReportId'} // die;
			next if exists $cdcReports{$cdcReportInternalId}->{'detailsTimestamp'};
			$reportsByIds{$cdcReportId} = 1;
		}
		my $packSize      = int($totalReports / $totalThreadsOnBulkDL);
		# say "packSize : $packSize";
		my $packNum       = 0;
		my $entriesInPack = 0;
		my %packs         = ();
		for my $cdcReportId (sort{$a <=> $b} keys %reportsByIds) {
			$entriesInPack++;
			$packs{$packNum}->{$cdcReportId} = 1;
			my $pPlusOne = $packNum + 1;
			if ($entriesInPack == $packSize && $pPlusOne != $totalThreadsOnBulkDL) {
				$entriesInPack = 0;
				$packNum++;
			}
		}
		my %threads = (); # Keeps track of the threads initiated.
		for my $packNum (sort{$a <=> $b} keys %packs) {
			my ($firstId, $lastId);
			for my $cdcReportId (sort{$a <=> $b} keys %{$packs{$packNum}}) {
				$firstId = $cdcReportId if !$firstId;
				$lastId  = $cdcReportId;
			}
			my $currentDatetime = time::current_datetime();
			say "$currentDatetime - Starting instance [$packNum], on chrome profile [$chromeProfileNum] from cdc report id [$firstId] to [$lastId]";
			$chromeProfileNum++;
			my $thread = Proc::Background->new('perl', 'tasks/cdc/get_us_bulk_reports.pl', $chromeProfileNum, $firstId, $lastId) || die "failed";
			$threads{$packNum}->{'thread'} = $thread;
			$threads{$packNum}->{'initiated'} = 1;
			# say "packNum : $packNum";
			# say "firstId : $firstId";
			# say "lastId  : $lastId";
			sleep 5;
		}
		my ($threadsFinished, $totalThreads) = (0, 0);
		$totalThreads = keys %threads;
		while ($threadsFinished < $totalThreads) {
			my $currentDatetime = time::current_datetime();
			STDOUT->printflush("\r$currentDatetime - Monitoring sub-threads [$threadsFinished / $totalThreads]");
			for my $packNum (keys %threads) {
				next if exists $threads{$packNum}->{'finished'};
				my $thread = $threads{$packNum}->{'thread'} // die;
				unless ($thread->alive) {
					$threads{$packNum}->{'finished'} = 1;
					$threadsFinished++;
				}
			}
			sleep 1;
		}
		$currentDatetime = time::current_datetime();
		STDOUT->printflush("\r$currentDatetime - Monitoring sub-threads [$threadsFinished / $totalThreads]");
		# p%packs;
	}
}