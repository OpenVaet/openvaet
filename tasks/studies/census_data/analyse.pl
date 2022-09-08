#!/usr/bin/perl
use strict;
use warnings;
use 5.30.0;
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
use Number::Format;
use Scalar::Util qw(looks_like_number);
use File::stat;
use lib "$FindBin::Bin/../../../lib";

# Project's libraries.
use config;
use global;
use time;

# Basic script config.
my $populationFile   = 'raw_data/nc-est2021-syasexn.csv';    # File containing "Annual Estimates of the Resident Population by Single Year of Age and Sex for the United States: April 1, 2020 to July 1, 2021"
														     # taken from https://www2.census.gov/programs-surveys/popest/tables/2020-2021/national/asrh/nc-est2021-syasexn.xlsx
														     # and converted to UTF8 ";" separated .CSV
my $vaxFile          = 'raw_data/COVID-19_Vaccination_and_Case_' .
					   'Trends_by_Age_Group__United_' .
					   'States.csv';                         # File containing the current vaccination statistics by age groups,
															 # taken from https://data.cdc.gov/api/views/gxj9-t96f/rows.csv?accessType=DOWNLOAD&bom=true&format=true&delimiter=%3B
															 # coming from https://data.cdc.gov/Vaccinations/COVID-19-Vaccination-and-Case-Trends-by-Age-Group-/gxj9-t96f
my $vaxBoostFile     = 'raw_data/COVID-19_Primary_Series_' .
					   'Completion__Booster_Dose_Eligibility__' .
					   'and_Booster_Dose_Receipt_by_Age__' .
					   'United_States.csv'; 			     # File containing 'COVID-19 Primary Series Completion, Booster Dose Eligibility, and Booster Dose Receipt by Age, United States'
														     # on https://data.cdc.gov/Vaccinations/COVID-19-Primary-Series-Completion-Booster-Dose-El/3pbe-qh9z
														     # direct link : https://data.cdc.gov/api/views/3pbe-qh9z/rows.csv?accessType=DOWNLOAD&bom=true&format=true&delimiter=%3B
my $altVaxBoostFile  = 'raw_data/COVID-19_Vaccination_Demographics' .
					   '_in_the_United_States_National.csv'; # File 'COVID-19 Vaccination Demographics in the United States,National', from https://data.cdc.gov/Vaccinations/COVID-19-Vaccination-Demographics-in-the-United-St/km4m-vcsb, feeding 
					   										 # https://covid.cdc.gov/covid-data-tracker/#vaccination-demographics-trends
															 # Direct link : https://data.cdc.gov/api/views/km4m-vcsb/rows.csv?accessType=DOWNLOAD&bom=true&format=true&delimiter=%3B

# Creating output folder.
my $outFolder  = 'stats';
make_path($outFolder) unless (-d $outFolder);

my %statistics = ();

# Init numbers format.
my $de = new Number::Format(-thousands_sep   => ' ',
                            -decimal_point   => '.');

# Loading population data.
my %populationByAges = ();
my %populationByAgeGroups = ();
load_population_age();

# Preparing age for vaccination's age groups.
my %ageGroups = ();
set_age_groups();
prepare_population_by_age_group();

# Loading vaccination data.
my %dosesByDatesAndAges = ();
my %dosesByDates = ();
load_vaccination_data();

# Loading booster vaccination data.
my %vaxByDates = ();
my %altVaxByDates = ();
load_booster_vaccination_data();
load_booster_vaccination_data_alt();

finalize_stats();

sub load_population_age {
	open my $in, '<:utf8', $populationFile;
	my $agesLoaded = 0;
	while (<$in>) {
		chomp $_;
		my ($age, $april20Population, $july20Population, $july21Population) = split ';', $_;
		next unless $age && $july21Population;
		next unless $age =~ /\..*/;
		$age =~ s/\.//;
		$age =~ s/\+//;
		$agesLoaded++;
		$july20Population =~ s/ //g;
		$july21Population =~ s/ //g;
		$populationByAges{$age}->{'july20Population'} = $july20Population;
		$populationByAges{$age}->{'july21Population'} = $july21Population;
		last if $agesLoaded == 101;
	}
	close $in;
	# p%populationByAges;
	# die;
}

sub set_age_groups {
	$ageGroups{'1'}->{'label'}  = '<2 Years';
	$ageGroups{'1'}->{'from'}   = '0';
	$ageGroups{'1'}->{'to'}     = '1';
	$ageGroups{'2'}->{'label'}  = '2 - 4 Years';
	$ageGroups{'2'}->{'from'}   = '2';
	$ageGroups{'2'}->{'to'}     = '4';
	$ageGroups{'3'}->{'label'}  = '5 - 11 Years';
	$ageGroups{'3'}->{'from'}   = '5';
	$ageGroups{'3'}->{'to'}     = '11';
	$ageGroups{'4'}->{'label'}  = '12 - 17 Years';
	$ageGroups{'4'}->{'from'}   = '12';
	$ageGroups{'4'}->{'to'}     = '17';
	$ageGroups{'5'}->{'label'}  = '18 - 24 Years';
	$ageGroups{'5'}->{'from'}   = '18';
	$ageGroups{'5'}->{'to'}     = '24';
	$ageGroups{'6'}->{'label'}  = '25 - 49 Years';
	$ageGroups{'6'}->{'from'}   = '25';
	$ageGroups{'6'}->{'to'}     = '49';
	$ageGroups{'7'}->{'label'}  = '50 - 64 Years';
	$ageGroups{'7'}->{'from'}   = '50';
	$ageGroups{'7'}->{'to'}     = '64';
	$ageGroups{'8'}->{'label'}  = '65+ Years';
	$ageGroups{'8'}->{'from'}   = '65';
}

sub prepare_population_by_age_group {
	my $population2021Total = 0;
	for my $ageGroupRef (sort{$a <=> $b} keys %ageGroups) {
		my $label = $ageGroups{$ageGroupRef}->{'label'} // die;
		my $from  = $ageGroups{$ageGroupRef}->{'from'}  // die;
		my $to;
		my ($july20Population, $july21Population) = (0, 0);
		for my $age (sort{$a <=> $b} keys %populationByAges) {
			next if $age < $from;
			if ($label ne '65+ Years') {
				$to    = $ageGroups{$ageGroupRef}->{'to'}    // die;
				next if $age > $to;
			}
			my $july20 = $populationByAges{$age}->{'july20Population'} // die;
			my $july21 = $populationByAges{$age}->{'july21Population'} // die;
			$july20Population += $july20;
			$july21Population += $july21;
			$population2021Total += $july21;
		}
		$populationByAgeGroups{$label}->{'ageGroupRef'} = $ageGroupRef;
		$populationByAgeGroups{$label}->{'july20Population'} = $july20Population;
		$populationByAgeGroups{$label}->{'july21Population'} = $july21Population;
		$statistics{'populationByAgeGroups'}->{'populationFile'}->{'july20Total'} += $july20Population;
		$statistics{'populationByAgeGroups'}->{'populationFile'}->{'july21Total'} += $july21Population;
		$statistics{'populationByAgeGroups'}->{'populationFile'}->{'ageGroups'}->{$ageGroupRef}->{'label'} = $label;
		$statistics{'populationByAgeGroups'}->{'populationFile'}->{'ageGroups'}->{$ageGroupRef}->{'july20Population'} = $july20Population;
		$statistics{'populationByAgeGroups'}->{'populationFile'}->{'ageGroups'}->{$ageGroupRef}->{'july21Population'} = $july21Population;
	}
	# p%statistics;
}

sub load_vaccination_data {
	my ($highestDate, $lowestDate) = (0, 99999999);
	my %dosesByDatesAgeGroups = ();
	my %agesGroups = ();
	open my $in, '<:utf8', $vaxFile;
	my $agesLoaded = 0;
	while (<$in>) {
		chomp $_;
		my ($date, $ageGroup, $casePer100K, $dose1Base1, $dose2Base1) = split ';', $_;
		my ($month, $day, $year) = $date =~ /(..)\/(..)\/(....)/;
		next unless $month && $day && $year;
		my $referenceYear;
		if ($year eq '2022' || $year eq '2021') {
			$referenceYear = '21';
		} elsif ($year eq '2020') {
			$referenceYear = '20';
		} else {
			die "year : $year";
		}
		my $population = $populationByAgeGroups{$ageGroup}->{"july$referenceYear" . "Population"} // next;
		my $ageGroupRef = $populationByAgeGroups{$ageGroup}->{'ageGroupRef'} // die;
		$agesGroups{$ageGroup} = 1;
		$date = "$year-$month-$day";
		my $compDate = $date;
		$compDate =~ s/\D//g;
		$highestDate = $compDate if $compDate > $highestDate;
		$lowestDate  = $compDate if $compDate < $lowestDate;
		$dosesByDatesAgeGroups{$compDate}->{'date'} = $date;
		$dosesByDatesAgeGroups{$compDate}->{'ageGroups'}->{$ageGroup}->{'population'}  = $population;
		$dosesByDatesAgeGroups{$compDate}->{'ageGroups'}->{$ageGroup}->{'ageGroupRef'} = $ageGroupRef;
	}
	close $in;
	my ($hY, $hM, $hD) = $highestDate =~ /(....)(..)(..)/;
	my ($lY, $lM, $lD) = $lowestDate  =~ /(....)(..)(..)/;
	$highestDate = "$hY-$hM-$hD";
	$lowestDate  = "$lY-$lM-$lD";
	my %currentDosesByGroups = ();
	for my $compDate (sort{$a <=> $b} keys %dosesByDatesAgeGroups) {
		my $date = $dosesByDatesAgeGroups{$compDate}->{'date'} // die;
		my ($year, $month, $day) = split '-', $date;
		for my $ageGroup (sort keys %agesGroups) {
			my ($doses1Administered, $doses2Administered, $population, $ageGroupRef);
			if (exists $dosesByDatesAgeGroups{$compDate}->{'ageGroups'}->{$ageGroup}->{'population'}) {
				$population  = $dosesByDatesAgeGroups{$compDate}->{'ageGroups'}->{$ageGroup}->{'population'}  // die;
				$ageGroupRef = $dosesByDatesAgeGroups{$compDate}->{'ageGroups'}->{$ageGroup}->{'ageGroupRef'} // die;
				$currentDosesByGroups{$ageGroup}->{'ageGroupRef'} = $ageGroupRef;
				$currentDosesByGroups{$ageGroup}->{'population'}  = $population;
			} else {
				$ageGroupRef = $currentDosesByGroups{$ageGroup}->{'ageGroupRef'} // die "ageGroup : $ageGroup";
				$population  = $currentDosesByGroups{$ageGroup}->{'population'}  // die "ageGroup : $ageGroup";
			}
			# say "$date - $ageGroup - $doses1Administered - $doses2Administered";
			$dosesByDates{$date}->{'weekNumber'} = iso_week_number($date);
			$dosesByDates{$date}->{'population'}  += $population;
			$dosesByDates{$date}->{'ageGroupRef'} += $ageGroupRef;
			$dosesByDatesAndAges{$date}->{$ageGroup}->{'weekNumber'}  = iso_week_number("$year-$month-$day");
			$dosesByDatesAndAges{$date}->{$ageGroup}->{'population'}  = $population;
			$dosesByDatesAndAges{$date}->{$ageGroup}->{'ageGroupRef'} = $ageGroupRef;
		}
	}
	# p%dosesByDatesAndAges;
	# say "highestDate : $highestDate";
	# say "lowestDate  : $lowestDate";
	# die;
}

sub load_booster_vaccination_data {
	open my $in, '<:utf8', $vaxBoostFile;
	while (<$in>) {
		chomp $_;
		my ($date, $demographicCategory, $census, $seriesComplete, $seriesCompletePopPercent,
			$firstBoosterEligible, $firstBoosterEligiblePopPercent, $firstBooster, $firstBoosterPopPercent,
			$secondBoosterEligible, $secondBoosterEligiblePopPercent, $secondBooster, $secondBoosterPopPercent) = split ';', $_;
		next if $demographicCategory eq 'Demographic_category';
		my ($month, $day, $year) = $date =~ /(.*)\/(.*)\/(.*) ..:..:.. ../;
		die unless $month && $day && $year;
		$date = "$year$month$day";
		next if $demographicCategory eq 'Ages_5+';
		$demographicCategory = translate_alt_demographic_cat($demographicCategory);
		$vaxByDates{$date}->{$demographicCategory}->{'updateDate'} = $date;
		$vaxByDates{$date}->{$demographicCategory}->{'census'} = $census;
		$vaxByDates{$date}->{$demographicCategory}->{'seriesComplete'} = $seriesComplete;
		$vaxByDates{$date}->{$demographicCategory}->{'seriesCompletePopPercent'} = $seriesCompletePopPercent;
		$vaxByDates{$date}->{$demographicCategory}->{'firstBoosterEligible'} = $firstBoosterEligible;
		$vaxByDates{$date}->{$demographicCategory}->{'firstBoosterEligiblePopPercent'} = $firstBoosterEligiblePopPercent;
		$vaxByDates{$date}->{$demographicCategory}->{'firstBooster'} = $firstBooster;
		$vaxByDates{$date}->{$demographicCategory}->{'firstBoosterPopPercent'} = $firstBoosterPopPercent;
		$vaxByDates{$date}->{$demographicCategory}->{'secondBoosterEligible'} = $secondBoosterEligible;
		$vaxByDates{$date}->{$demographicCategory}->{'secondBoosterEligiblePopPercent'} = $secondBoosterEligiblePopPercent;
		$vaxByDates{$date}->{$demographicCategory}->{'secondBooster'} = $secondBooster;
		$vaxByDates{$date}->{$demographicCategory}->{'secondBoosterPopPercent'} = $secondBoosterPopPercent;
	}
	close $in;
	for my $date (sort{$a <=> $b} keys %vaxByDates) {
		for my $demographicCategory (sort keys %{$vaxByDates{$date}}) {
			for my $label (sort keys %{$vaxByDates{$date}->{$demographicCategory}}) {
				my $val = $vaxByDates{$date}->{$demographicCategory}->{$label} // die;
				$val =~ s/\,//g;
				$vaxByDates{$date}->{$demographicCategory}->{$label} = $val;
			}
			my %obj = %{$vaxByDates{$date}->{$demographicCategory}};
			$statistics{'populationByAgeGroups'}->{'vaxBoostFile'}->{'ageGroups'}->{$demographicCategory} = \%obj;
		}
	}
}

sub translate_alt_demographic_cat {
	my ($demographicCategory) = @_;
	my $demCat;
	if ($demographicCategory eq 'Ages_<2yrs') {
		$demCat = '<2 Years';
	} elsif ($demographicCategory eq 'Ages_<5yrs') {
		$demCat = '<5 Years';
	} elsif ($demographicCategory eq 'Ages_<12yrs') {
		$demCat = '<12 Years';
	} elsif ($demographicCategory eq 'Ages_2-4_yrs') {
		$demCat = '2 - 4 Years';
	} elsif ($demographicCategory eq 'Ages_5-11' || $demographicCategory eq 'Ages_5-11_yrs') {
		$demCat = '5 - 11 Years';
	} elsif ($demographicCategory eq 'Ages_12-15_yrs') {
		$demCat = '12 - 15 Years';
	} elsif ($demographicCategory eq 'Ages_12-17' || $demographicCategory eq 'Ages_12-17_yrs') {
		$demCat = '12 - 17 Years';
	} elsif ($demographicCategory eq 'Ages_16-17_yrs') {
		$demCat = '16 - 17 Years';
	} elsif ($demographicCategory eq 'Ages_18-24_yrs') {
		$demCat = '18 - 24 Years';
	} elsif ($demographicCategory eq 'Ages_18-49') {
		$demCat = '18 - 49 Years';
	} elsif ($demographicCategory eq 'Ages_25-39_yrs') {
		$demCat = '25 - 39 Years';
	} elsif ($demographicCategory eq 'Ages_25-49_yrs') {
		$demCat = '25 - 49 Years';
	} elsif ($demographicCategory eq 'Ages_40-49_yrs') {
		$demCat = '40 - 49 Years';
	} elsif ($demographicCategory eq 'Ages_50-64' || $demographicCategory eq 'Ages_50-64_yrs') {
		$demCat = '50 - 64 Years';
	} elsif ($demographicCategory eq 'Ages_65+' || $demographicCategory eq 'Ages_65+_yrs') {
		$demCat = '65+ Years';
	} elsif ($demographicCategory eq 'Ages_65-74_yrs') {
		$demCat = '65 - 74 Years';
	} elsif ($demographicCategory eq 'Ages_75+_yrs') {
		$demCat = '75+ Years';
	} elsif ($demographicCategory eq 'Age_unknown') {
		$demCat = 'Unknown';
	} elsif ($demographicCategory eq 'Age_known') {
		$demCat = 'Known';
	} elsif ($demographicCategory eq 'US') {
		$demCat = 'US';
	} else {
		die "demographicCategory : $demographicCategory";
	}
	return $demCat;
}

sub load_booster_vaccination_data_alt {
	open my $in, '<:utf8', $altVaxBoostFile;
	while (<$in>) {
		chomp $_;
		my ($date,
			$demographicCategory,
			$doses1Administered,
			$doses1AdministeredPercentKnown,
			$doses1AdministeredPercentUS,
			$seriesCompleteYes,
			$doses1AdministeredPercentAgeGroup,
			$seriesCompletePopPercentAgeGroup,
			$seriesCompletePopPercentKnown,
			$seriesCompletePopPercentUS,
			$boosterDosesVaxPercentAgeGroup,
			$boosterDosesVaxPercentKnown,
			$boosterDosesVaxPercentUS,
			$boosterDosesVaxPercentKnownLast14Days,
			$boosterDosesYes,
			$boosterDosesYesLast14Days,
			$secondBoosterDosesVaxPercentAgeGroup,
			$secondBoosterDosesVaxPercentKnown,
			$secondBoosterDosesVaxPercentUS,
			$secondBoosterDosesVaxPercentKnownLast14Days,
			$secondBoosterDosesYes,
			$secondBoosterDosesYesLast14Days
		) = split ';', $_;
		next if $demographicCategory eq 'Demographic_category';
		my ($month, $day, $year) = $date =~ /(.*)\/(.*)\/(.*)/;
		next unless $demographicCategory =~ /Ages_/ || $demographicCategory =~ /Age_/ || $demographicCategory eq 'US';
		die unless $month && $day && $year;
		$date = "$year$month$day";
		$demographicCategory = translate_alt_demographic_cat($demographicCategory);
		$altVaxByDates{$date}->{$demographicCategory}->{'updateDate'} = $date;
		$altVaxByDates{$date}->{$demographicCategory}->{'doses1Administered'} = $doses1Administered;
		$altVaxByDates{$date}->{$demographicCategory}->{'doses1AdministeredPercentKnown'} = $doses1AdministeredPercentKnown;
		$altVaxByDates{$date}->{$demographicCategory}->{'doses1AdministeredPercentUS'} = $doses1AdministeredPercentUS;
		$altVaxByDates{$date}->{$demographicCategory}->{'seriesCompleteYes'} = $seriesCompleteYes;
		$altVaxByDates{$date}->{$demographicCategory}->{'doses1AdministeredPercentAgeGroup'} = $doses1AdministeredPercentAgeGroup;
		$altVaxByDates{$date}->{$demographicCategory}->{'seriesCompletePopPercentAgeGroup'} = $seriesCompletePopPercentAgeGroup;
		$altVaxByDates{$date}->{$demographicCategory}->{'seriesCompletePopPercentKnown'} = $seriesCompletePopPercentKnown;
		$altVaxByDates{$date}->{$demographicCategory}->{'seriesCompletePopPercentUS'} = $seriesCompletePopPercentUS;
		$altVaxByDates{$date}->{$demographicCategory}->{'boosterDosesVaxPercentAgeGroup'} = $boosterDosesVaxPercentAgeGroup;
		$altVaxByDates{$date}->{$demographicCategory}->{'boosterDosesVaxPercentKnown'} = $boosterDosesVaxPercentKnown;
		$altVaxByDates{$date}->{$demographicCategory}->{'boosterDosesVaxPercentUS'} = $boosterDosesVaxPercentUS;
		$altVaxByDates{$date}->{$demographicCategory}->{'boosterDosesVaxPercentKnownLast14Days'} = $boosterDosesVaxPercentKnownLast14Days;
		$altVaxByDates{$date}->{$demographicCategory}->{'boosterDosesYes'} = $boosterDosesYes;
		$altVaxByDates{$date}->{$demographicCategory}->{'boosterDosesYesLast14Days'} = $boosterDosesYesLast14Days;
		$altVaxByDates{$date}->{$demographicCategory}->{'secondBoosterDosesVaxPercentAgeGroup'} = $secondBoosterDosesVaxPercentAgeGroup;
		$altVaxByDates{$date}->{$demographicCategory}->{'secondBoosterDosesVaxPercentKnown'} = $secondBoosterDosesVaxPercentKnown;
		$altVaxByDates{$date}->{$demographicCategory}->{'secondBoosterDosesVaxPercentUS'} = $secondBoosterDosesVaxPercentUS;
		$altVaxByDates{$date}->{$demographicCategory}->{'secondBoosterDosesVaxPercentKnownLast14Days'} = $secondBoosterDosesVaxPercentKnownLast14Days;
		$altVaxByDates{$date}->{$demographicCategory}->{'secondBoosterDosesYes'} = $secondBoosterDosesYes;
		$altVaxByDates{$date}->{$demographicCategory}->{'secondBoosterDosesYesLast14Days'} = $secondBoosterDosesYesLast14Days;
	}
	close $in;

	# Cleaning values.
	for my $date (sort{$a <=> $b} keys %altVaxByDates) {
		for my $demographicCategory (sort keys %{$altVaxByDates{$date}}) {
			for my $label (sort keys %{$altVaxByDates{$date}->{$demographicCategory}}) {
				my $val = $altVaxByDates{$date}->{$demographicCategory}->{$label} // die;
				$val =~ s/\,//g;
				$altVaxByDates{$date}->{$demographicCategory}->{$label} = $val;
			}
			my %obj = %{$altVaxByDates{$date}->{$demographicCategory}};
			$statistics{'populationByAgeGroups'}->{'altVaxBoostFile'}->{'ageGroups'}->{$demographicCategory} = \%obj;
		}
	}
}

sub finalize_stats {

	# Fething the offsets between age groups 2020 - 2021.
	for my $ageGroupRef (sort{$a <=> $b} keys %{$statistics{'populationByAgeGroups'}->{'populationFile'}->{'ageGroups'}}) {
		my $offset  = $statistics{'populationByAgeGroups'}->{'populationFile'}->{'ageGroups'}->{$ageGroupRef}->{'july21Population'} - $statistics{'populationByAgeGroups'}->{'populationFile'}->{'ageGroups'}->{$ageGroupRef}->{'july20Population'};
		my $label   = $statistics{'populationByAgeGroups'}->{'populationFile'}->{'ageGroups'}->{$ageGroupRef}->{'label'}  // die;
		$statistics{'populationByAgeGroups'}->{'populationFile'}->{'ageGroups'}->{$ageGroupRef}->{'offset21-20'}          = $offset; 
		$statistics{'populationByAgeGroups'}->{'populationFile'}->{'ageGroups'}->{$ageGroupRef}->{'offset21-20Formatted'} = $de->format_number($offset);
		$statistics{'populationByAgeGroups'}->{'populationFile'}->{'ageGroups'}->{$ageGroupRef}->{'july20PopulationFormatted'} = $de->format_number($statistics{'populationByAgeGroups'}->{'populationFile'}->{'ageGroups'}->{$ageGroupRef}->{'july20Population'});
		$statistics{'populationByAgeGroups'}->{'populationFile'}->{'ageGroups'}->{$ageGroupRef}->{'july21PopulationFormatted'} = $de->format_number($statistics{'populationByAgeGroups'}->{'populationFile'}->{'ageGroups'}->{$ageGroupRef}->{'july21Population'});
	}

	# Fetching the offsets Current 1 - 2021.
	for my $ageGroup (sort keys %{$statistics{'populationByAgeGroups'}->{'vaxBoostFile'}->{'ageGroups'}}) {
		my $census = $statistics{'populationByAgeGroups'}->{'vaxBoostFile'}->{'ageGroups'}->{$ageGroup}->{'census'}  // die;
		my $offset;
		if ($ageGroup eq '18 - 49 Years') {
			my $ageGroupRef1 = $populationByAgeGroups{'18 - 24 Years'}->{'ageGroupRef'} // die;
			my $ageGroupRef2 = $populationByAgeGroups{'25 - 49 Years'}->{'ageGroupRef'} // die;
			$offset = $census - ($statistics{'populationByAgeGroups'}->{'populationFile'}->{'ageGroups'}->{$ageGroupRef1}->{'july21Population'} + $statistics{'populationByAgeGroups'}->{'populationFile'}->{'ageGroups'}->{$ageGroupRef2}->{'july21Population'});
		} elsif ($ageGroup ne 'Unknown') {
			my $ageGroupRef = $populationByAgeGroups{$ageGroup}->{'ageGroupRef'} // die "ageGroup : $ageGroup";
			$offset = $census - $statistics{'populationByAgeGroups'}->{'populationFile'}->{'ageGroups'}->{$ageGroupRef}->{'july21Population'};
		} else {
			# No offset to calculate on unknown.
		}
		$statistics{'populationByAgeGroups'}->{'vaxBoostFile'}->{'ageGroups'}->{$ageGroup}->{'offsetCurrent-21'} = $offset;
		if (defined $offset) {
			$statistics{'populationByAgeGroups'}->{'vaxBoostFile'}->{'ageGroups'}->{$ageGroup}->{'offsetCurrent-21Formatted'} = $de->format_number($offset); 
		} else {
			$statistics{'populationByAgeGroups'}->{'vaxBoostFile'}->{'ageGroups'}->{$ageGroup}->{'offsetCurrent-21Formatted'} = 0; 
		}
		if (defined $census && length $census >= 1) {
			$statistics{'populationByAgeGroups'}->{'vaxBoostFile'}->{'ageGroups'}->{$ageGroup}->{'censusFormatted'} = $de->format_number($census); 
		} else {
			$statistics{'populationByAgeGroups'}->{'vaxBoostFile'}->{'ageGroups'}->{$ageGroup}->{'censusFormatted'} = 0; 
		}
	}
	$statistics{'populationByAgeGroups'}->{'populationFile'}->{'july20TotalFormatted'} = $de->format_number($statistics{'populationByAgeGroups'}->{'populationFile'}->{'july20Total'});
	$statistics{'populationByAgeGroups'}->{'populationFile'}->{'july21TotalFormatted'} = $de->format_number($statistics{'populationByAgeGroups'}->{'populationFile'}->{'july21Total'});
	$statistics{'populationByAgeGroups'}->{'populationFile'}->{'offsetTotal'}          = $statistics{'populationByAgeGroups'}->{'populationFile'}->{'july21Total'} - $statistics{'populationByAgeGroups'}->{'populationFile'}->{'july20Total'}; 
	$statistics{'populationByAgeGroups'}->{'populationFile'}->{'offsetTotalFormatted'} = $de->format_number($statistics{'populationByAgeGroups'}->{'populationFile'}->{'july21Total'} - $statistics{'populationByAgeGroups'}->{'populationFile'}->{'july20Total'});

	# Fetching the offsets Current 2 - 2021 & Census flat values.
	for my $ageGroup (sort keys %{$statistics{'populationByAgeGroups'}->{'altVaxBoostFile'}->{'ageGroups'}}) {
		my $doses1Administered = $statistics{'populationByAgeGroups'}->{'altVaxBoostFile'}->{'ageGroups'}->{$ageGroup}->{'doses1Administered'} // die;
		my $doses1AdministeredPercentAgeGroup = $statistics{'populationByAgeGroups'}->{'altVaxBoostFile'}->{'ageGroups'}->{$ageGroup}->{'doses1AdministeredPercentAgeGroup'} // die;
		my $census;
		if (defined $doses1Administered && length $doses1Administered >= 1 && defined $doses1AdministeredPercentAgeGroup && length $doses1AdministeredPercentAgeGroup >= 1) {
			$census = nearest(1, $doses1Administered * 100 / $doses1AdministeredPercentAgeGroup);
		}
		$statistics{'populationByAgeGroups'}->{'altVaxBoostFile'}->{'ageGroups'}->{$ageGroup}->{'census'} = $census;
		my $offset;
		if ($ageGroup ne 'Unknown' || $ageGroup ne 'Known') {
			my $ageGroupRef = $populationByAgeGroups{$ageGroup}->{'ageGroupRef'};
			if ($ageGroup ne 'US') {
				if ($ageGroupRef) {
					die unless $census;
					$offset = $census - $statistics{'populationByAgeGroups'}->{'populationFile'}->{'ageGroups'}->{$ageGroupRef}->{'july21Population'};
				}
			} else {
				die unless $census;
				$offset = $census - $statistics{'populationByAgeGroups'}->{'populationFile'}->{'july21Total'};
			}
		} else {
			# No offset to calculate on unknown.
		}
		$statistics{'populationByAgeGroups'}->{'altVaxBoostFile'}->{'ageGroups'}->{$ageGroup}->{'offsetCurrent-21'} = $offset;
		if (defined $offset) {
			$statistics{'populationByAgeGroups'}->{'altVaxBoostFile'}->{'ageGroups'}->{$ageGroup}->{'offsetCurrent-21Formatted'} = $de->format_number($offset); 
		} else {
			$statistics{'populationByAgeGroups'}->{'altVaxBoostFile'}->{'ageGroups'}->{$ageGroup}->{'offsetCurrent-21Formatted'} = 0; 
		}
		if (defined $census && length $census >= 1) {
			$statistics{'populationByAgeGroups'}->{'altVaxBoostFile'}->{'ageGroups'}->{$ageGroup}->{'censusFormatted'} = $de->format_number($census); 
		} else {
			$statistics{'populationByAgeGroups'}->{'altVaxBoostFile'}->{'ageGroups'}->{$ageGroup}->{'censusFormatted'} = 0; 
		}
	}

	# Printing dates & other stats.
	open my $out, '>:utf8', 'stats/census_data.json';
	print $out encode_json\%statistics;
	close $out;
}