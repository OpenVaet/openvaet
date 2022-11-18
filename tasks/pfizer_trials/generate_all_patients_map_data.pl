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
use Date::DayOfWeek;
use Date::WeekNumber qw/ iso_week_number /;
use JSON;
use FindBin;
use lib "$FindBin::Bin/../../lib";

# Loading sites data.
my %sites        = ();
config_sites();

# Loading patients data.
my %patients     = ();
my %stats        = ();
load_patients();

my $totalPatients = 0;
my $earliestDate  = '99999999';
for my $patientId (sort keys %patients) {
	my ($siteCode)              = $patientId =~ /........ (....) ......../;
	my $siteName                = $sites{$siteCode}->{'name'}                        // die "siteCode : $siteCode";
	my $ageYears                = $patients{$patientId}->{'ageYears'}                // die;
	my $hasHIV                  = $patients{$patientId}->{'hasHIV'}                  // die;
	my $isPhase1                = $patients{$patientId}->{'isPhase1'}                // die;
	my $randomizationGroup      = $patients{$patientId}->{'randomizationGroup'}      // 'Undetermined';
	my $randomizationDate       = $patients{$patientId}->{'randomizationDate'}       // die;
	my $randomizationMonth      = $patients{$patientId}->{'randomizationMonth'}      // die;
	my $randomizationPageNumber = $patients{$patientId}->{'randomizationPageNumber'} // die;
	my $randomizationWeekNumber = $patients{$patientId}->{'randomizationWeekNumber'} // die;
	my $randomizationYear       = $patients{$patientId}->{'randomizationYear'}       // die;
	my $screeningDate           = $patients{$patientId}->{'screeningDate'}           // die;
	my $screeningMonth          = $patients{$patientId}->{'screeningMonth'}          // die;
	my $screeningWeekNumber     = $patients{$patientId}->{'screeningWeekNumber'}     // die;
	my $screeningYear           = $patients{$patientId}->{'screeningYear'}           // die;
	my $sex                     = $patients{$patientId}->{'sex'}                     // die;
	my $trialSubjectsPageNumber = $patients{$patientId}->{'trialSubjectsPageNumber'} // die;
	for my $doseNumber (sort{$a <=> $b} keys %{$patients{$patientId}->{'doses'}}) {
		my $dosage         = $patients{$patientId}->{'doses'}->{$doseNumber}->{'dosage'};
		my $dose           = $patients{$patientId}->{'doses'}->{$doseNumber}->{'dose'}           // die;
		my $doseDate       = $patients{$patientId}->{'doses'}->{$doseNumber}->{'doseDate'}       // die;
		$earliestDate      = $doseDate if $doseDate < $earliestDate;
		my $doseMonth      = $patients{$patientId}->{'doses'}->{$doseNumber}->{'doseMonth'}      // die;
		my $doseWeekNumber = $patients{$patientId}->{'doses'}->{$doseNumber}->{'doseWeekNumber'} // die;
		my $doseYear       = $patients{$patientId}->{'doses'}->{$doseNumber}->{'doseYear'}       // die;
	}
	my $latitude     = $sites{$siteCode}->{'latitude'}     // die;
	my $longitude    = $sites{$siteCode}->{'longitude'}    // die;
	my $investigator = $sites{$siteCode}->{'investigator'} // die;
	my $address      = $sites{$siteCode}->{'address'};
	my $postalCode   = $sites{$siteCode}->{'postalCode'};
	my $city         = $sites{$siteCode}->{'city'};
	# say "$siteNum -> $siteCode, $countryData -> $countryCode3, $age, $sex";
	# $stats{'By Ages'}->{$age}++;
	# $stats{'By Sexes'}->{$sex}++;
	$stats{'By Sites Codes'}->{$siteCode}->{'totalCases'}++;
	$stats{'By Sites Codes'}->{$siteCode}->{'address'}      = $address;
	$stats{'By Sites Codes'}->{$siteCode}->{'postalCode'}   = $postalCode;
	$stats{'By Sites Codes'}->{$siteCode}->{'city'}         = $city;
	$stats{'By Sites Codes'}->{$siteCode}->{'latitude'}     = $latitude;
	$stats{'By Sites Codes'}->{$siteCode}->{'longitude'}    = $longitude;
	$stats{'By Sites Codes'}->{$siteCode}->{'investigator'} = $investigator;
	$stats{'By Sites Codes'}->{$siteCode}->{'siteName'}     = $siteName;
	$stats{'Screenings By Dates'}->{$randomizationGroup}->{$screeningYear}->{$screeningWeekNumber}->{'totalCases'}++;
	# p$patients{$patientId};
	# die;
	$totalPatients++;
}
say "total patients : $totalPatients";
say "earliest date  : $earliestDate";

# Printing the usable files.
open my $out, '>:utf8', 'public/doc/pfizer_trial_cases_mapping/all_patients_data_by_sites.csv';
say $out "site code;site name;total cases;latitude;longitude;address;postal code;city;";
my @sitesData = ();
for my $siteCode (sort keys %{$stats{'By Sites Codes'}}) {
	my $latitude     = $stats{'By Sites Codes'}->{$siteCode}->{'latitude'};
	my $longitude    = $stats{'By Sites Codes'}->{$siteCode}->{'longitude'};
	my $siteName     = $stats{'By Sites Codes'}->{$siteCode}->{'siteName'}     // die;
	my $address      = $stats{'By Sites Codes'}->{$siteCode}->{'address'}      // die;
	my $postalCode   = $stats{'By Sites Codes'}->{$siteCode}->{'postalCode'}   // die;
	my $investigator = $stats{'By Sites Codes'}->{$siteCode}->{'investigator'} // die;
	my $city         = $stats{'By Sites Codes'}->{$siteCode}->{'city'}         // die;
	my $totalCases   = $stats{'By Sites Codes'}->{$siteCode}->{'totalCases'}   // die;
	say $out "$siteCode;$siteName;$totalCases;$latitude;$longitude;$address;$postalCode;$city;";
	my %o            = %{$stats{'By Sites Codes'}->{$siteCode}};
	$o{'siteCode'}   = $siteCode;
	push @sitesData, \%o;
}
close $out;
open my $jOut, '>:utf8', 'public/doc/pfizer_trial_cases_mapping/all_patients_data_by_sites.json';
print $jOut encode_json\@sitesData;
close $jOut;
open my $jOut2, '>:utf8', 'public/doc/pfizer_trial_cases_mapping/all_patients_stats_by_sites.json';
print $jOut2 encode_json\%stats;
close $jOut2;

open my $out2, '>:utf8', 'weekly_recruitments.csv';
for my $randomizationGroup (sort keys %{$stats{'Screenings By Dates'}}) {
	for my $year (sort{$a <=> $b} keys %{$stats{'Screenings By Dates'}->{$randomizationGroup}}) {
		for my $weekNumber (sort{$a <=> $b} keys %{$stats{'Screenings By Dates'}->{$randomizationGroup}->{$year}}) {
			my $totalCases = $stats{'Screenings By Dates'}->{$randomizationGroup}->{$year}->{$weekNumber}->{'totalCases'} // die;
			say $out2 "$randomizationGroup;$year - $weekNumber;$totalCases;";
		}
	}
}
close $out2;

# p%stats;

sub config_sites {
	# 1001
	$sites{'1001'}->{'name'}         = 'NYU Langone Health, Schwartz Health Care Center';
	$sites{'1001'}->{'address'}      = '530 First Avenue, 12th Fl';
	$sites{'1001'}->{'postalCode'}   = 'NEW YORK 10016';
	$sites{'1001'}->{'city'}         = 'New York';
	$sites{'1001'}->{'investigator'} = 'Mark Mulligan';
	$sites{'1001'}->{'latitude'}     = '40.741560';
	$sites{'1001'}->{'longitude'}    = '-73.975072';
	# 1002
	$sites{'1002'}->{'name'}         = 'University of Maryland, Center for Vaccine Development and Global Health';
	$sites{'1002'}->{'address'}      = '685 W. Baltimore St., HSF I, 4th Fl';
	$sites{'1002'}->{'postalCode'}   = 'MARYLAND 21201';
	$sites{'1002'}->{'city'}         = 'Baltimore';
	$sites{'1002'}->{'investigator'} = 'Kathleen Neuzil';
	$sites{'1002'}->{'latitude'}     = '39.289164';
	$sites{'1002'}->{'longitude'}    = '-76.625810';
	# 1003
	$sites{'1003'}->{'name'}         = 'Rochester Regional Health/Rochester General Hospital, Infectious Desease Department';
	$sites{'1003'}->{'address'}      = '1425 Portland Avenue';
	$sites{'1003'}->{'postalCode'}   = 'NY 14621';
	$sites{'1003'}->{'city'}         = 'Rochester';
	$sites{'1003'}->{'investigator'} = 'Edward Walsh';
	$sites{'1003'}->{'latitude'}     = '43.192742';
	$sites{'1003'}->{'longitude'}    = '-77.585667';
	# 1005
	$sites{'1005'}->{'name'}         = 'Rochester Clinical Research, Inc.';
	$sites{'1005'}->{'address'}      = '500 Helendale Rd, Ste 265';
	$sites{'1005'}->{'postalCode'}   = 'NY 14609';
	$sites{'1005'}->{'city'}         = 'Rochester, New York';
	$sites{'1005'}->{'investigator'} = 'Matthew Davis';
	$sites{'1005'}->{'latitude'}     = '43.179476';
	$sites{'1005'}->{'longitude'}    = '-77.545020';
	# 1006
	$sites{'1006'}->{'name'}         = 'J. Lewis Research Inc. / Foothill Family Clinic';
	$sites{'1006'}->{'address'}      = '2295 Foothill Dr';
	$sites{'1006'}->{'postalCode'}   = 'UT 84109';
	$sites{'1006'}->{'city'}         = 'Salt Lake City';
	$sites{'1006'}->{'investigator'} = 'James Peterson';
	$sites{'1006'}->{'latitude'}     = '40.721491';
	$sites{'1006'}->{'longitude'}    = '-111.811763';
	# 1007
	$sites{'1007'}->{'name'}         = 'Cincinnati Children\'s Hospital Medical Center';
	$sites{'1007'}->{'address'}      = '619 Oak St';
	$sites{'1007'}->{'postalCode'}   = 'OH 45206';
	$sites{'1007'}->{'city'}         = 'Cincinnati';
	$sites{'1007'}->{'investigator'} = 'Robert Frenck';
	$sites{'1007'}->{'latitude'}     = '39.129639';
	$sites{'1007'}->{'longitude'}    = '-84.497039';
	# 1008
	$sites{'1008'}->{'name'}         = 'Clinical Research Professionals';
	$sites{'1008'}->{'address'}      = '17998 Chesterfield Airport Rd, Ste 100';
	$sites{'1008'}->{'postalCode'}   = 'MO 63005';
	$sites{'1008'}->{'city'}         = 'Chesterfield';
	$sites{'1008'}->{'investigator'} = 'Timothy Jennings';
	$sites{'1008'}->{'latitude'}     = '38.669244';
	$sites{'1008'}->{'longitude'}    = '-90.634202';
	# 1009
	$sites{'1009'}->{'name'}         = 'J. Lewis Research Inc. / Foothill Family Clinic';
	$sites{'1009'}->{'address'}      = '2295 Foothill Dr';
	$sites{'1009'}->{'postalCode'}   = 'UT 84109';
	$sites{'1009'}->{'city'}         = 'Salt Lake City';
	$sites{'1009'}->{'investigator'} = 'Shane Christensen';
	$sites{'1009'}->{'latitude'}     = '40.721491';
	$sites{'1009'}->{'longitude'}    = '-111.811763';
	# 1011
	$sites{'1011'}->{'name'}         = 'Clinical Neuroscience Solutions, Inc';
	$sites{'1011'}->{'address'}      = '618 E. S St, Ste 100';
	$sites{'1011'}->{'postalCode'}   = 'FL 32801';
	$sites{'1011'}->{'city'}         = 'Orlando';
	$sites{'1011'}->{'investigator'} = 'Michael Dever';
	$sites{'1011'}->{'latitude'}     = '39.129639';
	$sites{'1011'}->{'longitude'}    = '-84.497039';
	# 1012
	$sites{'1012'}->{'name'}         = 'HOPE Research Institute';
	$sites{'1012'}->{'address'}      = '3900 E. Camelback Rd, Ste 125, 130 & 135';
	$sites{'1012'}->{'postalCode'}   = 'CT 06460';
	$sites{'1012'}->{'city'}         = 'Milford';
	$sites{'1012'}->{'investigator'} = 'Susann Varano';
	$sites{'1012'}->{'latitude'}     = '33.510857';
	$sites{'1012'}->{'longitude'}    = '-111.997874';
	# 1013
	$sites{'1013'}->{'name'}         = 'Clinical Neuroscience Solutions, Inc';
	$sites{'1013'}->{'address'}      = '618 E. S St, Ste 100';
	$sites{'1013'}->{'postalCode'}   = 'FL 32801';
	$sites{'1013'}->{'city'}         = 'Orlando';
	$sites{'1013'}->{'investigator'} = 'Michael Dever';
	$sites{'1013'}->{'latitude'}     = '28.537427';
	$sites{'1013'}->{'longitude'}    = '-81.368636';
	# 1015
	$sites{'1015'}->{'name'}         = 'Boston Medical Center';
	$sites{'1015'}->{'address'}      = '1 Boston Medical Center Pl., Shapiro Bldg. 9th Fl.';
	$sites{'1015'}->{'postalCode'}   = 'MA 02118';
	$sites{'1015'}->{'city'}         = 'Boston';
	$sites{'1015'}->{'investigator'} = 'Elizabeth Barnett';
	$sites{'1015'}->{'latitude'}     = '42.334403';
	$sites{'1015'}->{'longitude'}    = '-71.072164';
	# 1016
	$sites{'1016'}->{'name'}         = 'Kentucky Pediatric / Adult Research';
	$sites{'1016'}->{'address'}      = '201 S 5th St';
	$sites{'1016'}->{'postalCode'}   = 'KENTUCKY 40004';
	$sites{'1016'}->{'city'}         = 'Bardstown';
	$sites{'1016'}->{'investigator'} = 'Daniel Finn';
	$sites{'1016'}->{'latitude'}     = '37.808380';
	$sites{'1016'}->{'longitude'}    = '-85.470766';
	# 1018
	$sites{'1018'}->{'name'}         = 'Texas Center for Drug Development, Inc';
	$sites{'1018'}->{'address'}      = '6550 Mapleridge St, Ste 201, 206, 216, 220';
	$sites{'1018'}->{'postalCode'}   = 'TEXAS 77081';
	$sites{'1018'}->{'city'}         = 'San Antonio';
	$sites{'1018'}->{'investigator'} = 'Veronica Fragoso';
	$sites{'1018'}->{'latitude'}     = '29.709729';
	$sites{'1018'}->{'longitude'}    = '-95.474237';
	# 1019
	$sites{'1019'}->{'name'}         = 'Diagnostics Research Group';
	$sites{'1019'}->{'address'}      = '4410 Medical Dr, Ste 360';
	$sites{'1019'}->{'postalCode'}   = 'TEXAS 78229';
	$sites{'1019'}->{'city'}         = 'San Antonio';
	$sites{'1019'}->{'investigator'} = 'Charles Andrews';
	$sites{'1019'}->{'latitude'}     = '29.510245';
	$sites{'1019'}->{'longitude'}    = '-98.571134';
	# 1021
	$sites{'1021'}->{'name'}         = 'PMG Research of Raleigh, LLC';
	$sites{'1021'}->{'address'}      = '3521 Haworth Dr, Ste 100';
	$sites{'1021'}->{'postalCode'}   = 'NC 27609';
	$sites{'1021'}->{'city'}         = 'Raleigh';
	$sites{'1021'}->{'investigator'} = 'John Rubino';
	$sites{'1021'}->{'latitude'}     = '35.829084';
	$sites{'1021'}->{'longitude'}    = '-78.634895';
	# 1022
	$sites{'1022'}->{'name'}         = 'Wenatchee Valley Hospital, Clinical Research Department';
	$sites{'1022'}->{'address'}      = '820 N Chelan Ave';
	$sites{'1022'}->{'postalCode'}   = 'WA 98801';
	$sites{'1022'}->{'city'}         = 'Wenatchee';
	$sites{'1022'}->{'investigator'} = 'Steven Kaster';
	$sites{'1022'}->{'latitude'}     = '47.433778';
	$sites{'1022'}->{'longitude'}    = '-120.322236';
	# 1024
	$sites{'1024'}->{'name'}         = 'South Jersey Infectious Disease';
	$sites{'1024'}->{'address'}      = '730 Shore Rd';
	$sites{'1024'}->{'postalCode'}   = 'NJ 08244';
	$sites{'1024'}->{'city'}         = 'Somers Point';
	$sites{'1024'}->{'investigator'} = 'Christopher Lucasti';
	$sites{'1024'}->{'latitude'}     = '39.313707';
	$sites{'1024'}->{'longitude'}    = '-74.595725';
	# 1027
	$sites{'1027'}->{'name'}         = 'PharmQuest';
	$sites{'1027'}->{'address'}      = '806 Green Valley Rd, Ste 305';
	$sites{'1027'}->{'postalCode'}   = 'NC 27408';
	$sites{'1027'}->{'city'}         = 'Fargo';
	$sites{'1027'}->{'investigator'} = 'Alexander Murray';
	$sites{'1027'}->{'latitude'}     = '36.091044';
	$sites{'1027'}->{'longitude'}    = '-79.816062';
	# 1028
	$sites{'1028'}->{'name'}         = 'Lillestol Research LLC';
	$sites{'1028'}->{'address'}      = '4450 31st Ave S, Ste 101';
	$sites{'1028'}->{'postalCode'}   = 'ND 58104';
	$sites{'1028'}->{'city'}         = 'Fargo';
	$sites{'1028'}->{'investigator'} = 'Michael Lillestol';
	$sites{'1028'}->{'latitude'}     = '46.833424';
	$sites{'1028'}->{'longitude'}    = '-96.860613';
	# 1030
	$sites{'1030'}->{'name'}         = 'University Hospitals Cleveland Medical Center';
	$sites{'1030'}->{'address'}      = '11100 Euclid Ave';
	$sites{'1030'}->{'postalCode'}   = 'OH 44106';
	$sites{'1030'}->{'city'}         = 'Cleveland';
	$sites{'1030'}->{'investigator'} = 'Robert Salata';
	$sites{'1030'}->{'latitude'}     = '41.506408';
	$sites{'1030'}->{'longitude'}    = '-81.605679';
	# 1036
	$sites{'1036'}->{'name'}         = 'Trinity Clinical Research';
	$sites{'1036'}->{'address'}      = '709 NW Atlantic St';
	$sites{'1036'}->{'postalCode'}   = 'TN 37388';
	$sites{'1036'}->{'city'}         = 'Tullahoma';
	$sites{'1036'}->{'investigator'} = 'Marcus Lee';
	$sites{'1036'}->{'latitude'}     = '35.369091';
	$sites{'1036'}->{'longitude'}    = '-86.215992';
	# 1037
	$sites{'1037'}->{'name'}         = 'Clinical Neuroscience Solutions, Inc.';
	$sites{'1037'}->{'address'}      = '6401 poplar Ave, Ste 420';
	$sites{'1037'}->{'postalCode'}   = 'TN 38119';
	$sites{'1037'}->{'city'}         = 'Memphis';
	$sites{'1037'}->{'investigator'} = 'Lisa Usdan';
	$sites{'1037'}->{'latitude'}     = '35.099988';
	$sites{'1037'}->{'longitude'}    = '-89.849212';
	# 1038
	$sites{'1038'}->{'name'}         = 'Holston Medical Group';
	$sites{'1038'}->{'address'}      = '240 Medical Park Blvd, Ste 2600';
	$sites{'1038'}->{'postalCode'}   = 'TX 78726';
	$sites{'1038'}->{'city'}         = 'Austin';
	$sites{'1038'}->{'investigator'} = 'Rick Whiles';
	$sites{'1038'}->{'latitude'}     = '36.585121';
	$sites{'1038'}->{'longitude'}    = '-82.250162';
	# 1039
	$sites{'1039'}->{'name'}         = 'Arc Clinical Research at Wilson Parke';
	$sites{'1039'}->{'address'}      = '11714 Wilson Parke Ave., Ste 150';
	$sites{'1039'}->{'postalCode'}   = 'TX 78726';
	$sites{'1039'}->{'city'}         = 'Austin';
	$sites{'1039'}->{'investigator'} = 'Gretchen Crook';
	$sites{'1039'}->{'latitude'}     = '30.417878';
	$sites{'1039'}->{'longitude'}    = '-97.849751';
	# 1042
	$sites{'1042'}->{'name'}         = 'Benchmark Research';
	$sites{'1042'}->{'address'}      = '4504 Boat Club Rd, Ste #400A';
	$sites{'1042'}->{'postalCode'}   = 'TX 76135';
	$sites{'1042'}->{'city'}         = 'Forth Worth';
	$sites{'1042'}->{'investigator'} = 'William Seger';
	$sites{'1042'}->{'latitude'}     = '32.822397';
	$sites{'1042'}->{'longitude'}    = '-97.419301';
	# 1044
	$sites{'1044'}->{'name'}         = 'Virginia Research Center, LLC';
	$sites{'1044'}->{'address'}      = '13911 St. Francis Blvd., Ste 101';
	$sites{'1044'}->{'postalCode'}   = 'VA 23114';
	$sites{'1044'}->{'city'}         = 'Midlothian';
	$sites{'1044'}->{'investigator'} = 'Aaron Hartman';
	$sites{'1044'}->{'latitude'}     = '37.466735';
	$sites{'1044'}->{'longitude'}    = '-77.662634';
	# 1046
	$sites{'1046'}->{'name'}         = 'North Alabama Research Center, LLC';
	$sites{'1046'}->{'address'}      = '721 W Market St, Ste B';
	$sites{'1046'}->{'postalCode'}   = 'AL 35801';
	$sites{'1046'}->{'city'}         = 'Athens';
	$sites{'1046'}->{'investigator'} = 'Ernest Hendrix';
	$sites{'1046'}->{'latitude'}     = '34.803263';
	$sites{'1046'}->{'longitude'}    = '-86.980871';
	# 1048
	$sites{'1048'}->{'name'}         = 'Medical Affliated Research Center';
	$sites{'1048'}->{'address'}      = '2525 W. Greenway Rd, Ste 250';
	$sites{'1048'}->{'postalCode'}   = 'AZ 85023';
	$sites{'1048'}->{'city'}         = 'Phoenix';
	$sites{'1048'}->{'investigator'} = 'Adram Burgher';
	$sites{'1048'}->{'latitude'}     = '33.624359';
	$sites{'1048'}->{'longitude'}    = '-112.112400';
	# 1047
	$sites{'1047'}->{'name'}         = 'Medical Affliated Research Center';
	$sites{'1047'}->{'address'}      = '303 Williams Ave, Ste 511';
	$sites{'1047'}->{'postalCode'}   = 'AL 35801';
	$sites{'1047'}->{'city'}         = 'Huntsville';
	$sites{'1047'}->{'investigator'} = 'James McMurray';
	$sites{'1047'}->{'latitude'}     = '34.725469';
	$sites{'1047'}->{'longitude'}    = '-86.585356';
	# 1052
	$sites{'1052'}->{'name'}         = 'Long Beach Clinical Trials Services Inc.';
	$sites{'1052'}->{'address'}      = '2403 Atlantic Ave';
	$sites{'1052'}->{'postalCode'}   = 'CA 90057';
	$sites{'1052'}->{'city'}         = 'Los Angeles';
	$sites{'1052'}->{'investigator'} = 'Suzanne Fussell';
	$sites{'1052'}->{'latitude'}     = '33.800783';
	$sites{'1052'}->{'longitude'}    = '-118.185179';
	# 1054
	$sites{'1054'}->{'name'}         = 'National Research Institute';
	$sites{'1054'}->{'address'}      = '2010 Wilshire Blvd., Ste 302 and 809';
	$sites{'1054'}->{'postalCode'}   = 'CA 94598';
	$sites{'1054'}->{'city'}         = 'Los Angeles';
	$sites{'1054'}->{'investigator'} = 'Mark Leibowitz';
	$sites{'1054'}->{'latitude'}     = '34.057204';
	$sites{'1054'}->{'longitude'}    = '-118.274872';
	# 1055
	$sites{'1055'}->{'name'}         = 'Diablo Clinical Research, Inc.';
	$sites{'1055'}->{'address'}      = '2255 Ygnacio Valley Rd, Ste M';
	$sites{'1055'}->{'postalCode'}   = 'CA 94598';
	$sites{'1055'}->{'city'}         = 'Walnut Creek';
	$sites{'1055'}->{'investigator'} = 'Helen Stacey';
	$sites{'1055'}->{'latitude'}     = '37.922378';
	$sites{'1055'}->{'longitude'}    = '-122.030085';
	# 1056
	$sites{'1056'}->{'name'}         = 'Indago Research & Health Center, Inc.';
	$sites{'1056'}->{'address'}      = '3700 W 12th Ave, Ste 300';
	$sites{'1056'}->{'postalCode'}   = 'FL 33012';
	$sites{'1056'}->{'city'}         = 'Hialeah';
	$sites{'1056'}->{'investigator'} = 'Jose Cardona';
	$sites{'1056'}->{'latitude'}     = '25.855318';
	$sites{'1056'}->{'longitude'}    = '-80.307033';
	# 1057
	$sites{'1057'}->{'name'}         = 'Clinical Neurscience Solutions, Inc.';
	$sites{'1057'}->{'address'}      = '5200 Belfort Rd, Ste 420';
	$sites{'1057'}->{'postalCode'}   = 'FL 32256';
	$sites{'1057'}->{'city'}         = 'Jacksonville';
	$sites{'1057'}->{'investigator'} = 'Fadi Chalhoub';
	$sites{'1057'}->{'latitude'}     = '30.243625';
	$sites{'1057'}->{'longitude'}    = '-81.586714';
	# 1066
	$sites{'1066'}->{'name'}         = 'Solaris Clinical Research';
	$sites{'1066'}->{'address'}      = '1525 E. Leigh Field Dr, #100';
	$sites{'1066'}->{'postalCode'}   = 'ID 83646';
	$sites{'1066'}->{'city'}         = 'Meridian';
	$sites{'1066'}->{'investigator'} = 'David Butuk';
	$sites{'1066'}->{'latitude'}     = '43.641029';
	$sites{'1066'}->{'longitude'}    = '-116.375658';
	# 1068
	$sites{'1068'}->{'name'}         = 'Bozeman Health Deaconess Hospital dba Bozeman Health Clinical Research';
	$sites{'1068'}->{'address'}      = '915 Highland Blvd';
	$sites{'1068'}->{'postalCode'}   = 'MT 59715';
	$sites{'1068'}->{'city'}         = 'Bozeman';
	$sites{'1068'}->{'investigator'} = 'Andrew Gentry';
	$sites{'1068'}->{'latitude'}     = '45.668781';
	$sites{'1068'}->{'longitude'}    = '-111.018619';
	# 1071
	$sites{'1071'}->{'name'}         = 'Quality Clinical Research, Inc.';
	$sites{'1071'}->{'address'}      = '10040 Regency Cr, Ste 375';
	$sites{'1071'}->{'postalCode'}   = 'NE 68114';
	$sites{'1071'}->{'city'}         = 'Omaha';
	$sites{'1071'}->{'investigator'} = 'Michael Dunn';
	$sites{'1071'}->{'latitude'}     = '41.262811';
	$sites{'1071'}->{'longitude'}    = '-96.069489';
	# 1072
	$sites{'1072'}->{'name'}         = 'Optimal Research, LLC';
	$sites{'1072'}->{'address'}      = '2089 Cecil Ashburn Dr, Ste 203';
	$sites{'1072'}->{'postalCode'}   = 'AL 35802';
	$sites{'1072'}->{'city'}         = 'Huntsville';
	$sites{'1072'}->{'investigator'} = 'Randle Middleton';
	$sites{'1072'}->{'latitude'}     = '34.673102';
	$sites{'1072'}->{'longitude'}    = '-86.535652';
	# 1073
	$sites{'1073'}->{'name'}         = 'Alliance for Multispecialty Research, LLC';
	$sites{'1073'}->{'address'}      = '1492 S Mill Ave, Ste 312';
	$sites{'1073'}->{'postalCode'}   = 'Arizona 85281';
	$sites{'1073'}->{'city'}         = 'Tempe';
	$sites{'1073'}->{'investigator'} = 'Corey Anderson';
	$sites{'1073'}->{'latitude'}     = '33.412682';
	$sites{'1073'}->{'longitude'}    = '-111.942122';
	# 1077
	$sites{'1077'}->{'name'}         = 'Meridian Clinical Research LLC';
	$sites{'1077'}->{'address'}      = '409 Hooper Rd';
	$sites{'1077'}->{'postalCode'}   = 'NEW YORK 13760';
	$sites{'1077'}->{'city'}         = 'Endwell';
	$sites{'1077'}->{'investigator'} = 'Suchet Patel';
	$sites{'1077'}->{'latitude'}     = '42.114451';
	$sites{'1077'}->{'longitude'}    = '-76.017445';
	# 1079
	$sites{'1079'}->{'name'}         = 'PMG Research of Charlotte, LLC';
	$sites{'1079'}->{'address'}      = '1700 Abbey Place, Ste 201';
	$sites{'1079'}->{'postalCode'}   = 'NC 28209';
	$sites{'1079'}->{'city'}         = 'Charlotte';
	$sites{'1079'}->{'investigator'} = 'George Raad';
	$sites{'1079'}->{'latitude'}     = '35.169344';
	$sites{'1079'}->{'longitude'}    = '-80.847823';
	# 1080
	$sites{'1080'}->{'name'}         = 'PMG Research of Raleigh, LLC, d/b/a PMG';
	$sites{'1080'}->{'address'}      = '530 New Waverly Place, Ste 200A';
	$sites{'1080'}->{'postalCode'}   = 'NC 27518';
	$sites{'1080'}->{'city'}         = 'Cary';
	$sites{'1080'}->{'investigator'} = 'Sylvia Shoffner';
	$sites{'1080'}->{'latitude'}     = '35.737095';
	$sites{'1080'}->{'longitude'}    = '-78.776400';
	# 1081
	$sites{'1081'}->{'name'}         = 'Sterling Research Group, Ltd.';
	$sites{'1081'}->{'address'}      = '2230 Auburn Ave, Level B';
	$sites{'1081'}->{'postalCode'}   = 'OH 45219';
	$sites{'1081'}->{'city'}         = 'Cincinnati';
	$sites{'1081'}->{'investigator'} = 'Michael Butcher';
	$sites{'1081'}->{'latitude'}     = '39.123140';
	$sites{'1081'}->{'longitude'}    = '-84.508043';
	# 1082
	$sites{'1082'}->{'name'}         = 'Alliance for Multispecialty Research, LLC';
	$sites{'1082'}->{'address'}      = '1924 Alcoa Hwy, 4 and 5 Nw';
	$sites{'1082'}->{'postalCode'}   = 'TENNESSEE 37920';
	$sites{'1082'}->{'city'}         = 'Knoxville';
	$sites{'1082'}->{'investigator'} = 'William Smith';
	$sites{'1082'}->{'latitude'}     = '35.941513';
	$sites{'1082'}->{'longitude'}    = '-83.945188';
	# 1083
	$sites{'1083'}->{'name'}         = 'Benchmark Research';
	$sites{'1083'}->{'address'}      = '3100 Red River St, Ste 1';
	$sites{'1083'}->{'postalCode'}   = 'TX 78705';
	$sites{'1083'}->{'city'}         = 'Austin';
	$sites{'1083'}->{'investigator'} = 'Laurence Chu';
	$sites{'1083'}->{'latitude'}     = '30.290425';
	$sites{'1083'}->{'longitude'}    = '-97.728125';
	# 1084
	$sites{'1084'}->{'name'}         = 'Clinical Trials of Texas, Inc.';
	$sites{'1084'}->{'address'}      = '5430 Fredericksburgs Rd, Trlr';
	$sites{'1084'}->{'postalCode'}   = 'TX 78229';
	$sites{'1084'}->{'city'}         = 'San Antonio';
	$sites{'1084'}->{'investigator'} = 'Douglas Denham';
	$sites{'1084'}->{'latitude'}     = '29.506873';
	$sites{'1084'}->{'longitude'}    = '-98.563588';
	# 1085
	$sites{'1085'}->{'name'}         = 'Ventavia Research Group, LLC';
	$sites{'1085'}->{'address'}      = '300 N Rufe Snow Dr';
	$sites{'1085'}->{'postalCode'}   = 'TX 76248';
	$sites{'1085'}->{'city'}         = 'Keller';
	$sites{'1085'}->{'investigator'} = 'Gregory Fuller';
	$sites{'1085'}->{'latitude'}     = '32.937803';
	$sites{'1085'}->{'longitude'}    = '-97.229835';
	# 1087
	$sites{'1087'}->{'name'}         = 'PMG Research of Hickory, LLC';
	$sites{'1087'}->{'address'}      = '1907 Tradd Court';
	$sites{'1087'}->{'postalCode'}   = 'NC 28401';
	$sites{'1087'}->{'city'}         = 'Wilmington';
	$sites{'1087'}->{'investigator'} = 'Kevin Cannon';
	$sites{'1087'}->{'latitude'}     = '34.208389';
	$sites{'1087'}->{'longitude'}    = '-77.927732';
	# 1088
	$sites{'1088'}->{'name'}         = 'PMG Research of Hickory, LLC';
	$sites{'1088'}->{'address'}      = '221 13th Ave P1 NW, Ste 201';
	$sites{'1088'}->{'postalCode'}   = 'NC 28601';
	$sites{'1088'}->{'city'}         = 'Hickory';
	$sites{'1088'}->{'investigator'} = 'John Earl';
	$sites{'1088'}->{'latitude'}     = '35.750340';
	$sites{'1088'}->{'longitude'}    = '-81.341019';
	# 1089
	$sites{'1089'}->{'name'}         = 'PMG Research of Salisbury, LLC';
	$sites{'1089'}->{'address'}      = '410 Mocksville Ave';
	$sites{'1089'}->{'postalCode'}   = 'NC 28144';
	$sites{'1089'}->{'city'}         = 'Salisbury';
	$sites{'1089'}->{'investigator'} = 'Cecil Farrington';
	$sites{'1089'}->{'latitude'}     = '35.680044';
	$sites{'1089'}->{'longitude'}    = '-80.471300';
	# 1090
	$sites{'1090'}->{'name'}         = 'M3 Wake Research, Inc';
	$sites{'1090'}->{'address'}      = '3100 Duraleigh Rd, Ste 304';
	$sites{'1090'}->{'postalCode'}   = 'NC 27612';
	$sites{'1090'}->{'city'}         = 'Raleigh';
	$sites{'1090'}->{'investigator'} = 'Lisa Cohen';
	$sites{'1090'}->{'latitude'}     = '35.823982';
	$sites{'1090'}->{'longitude'}    = '-78.705544';
	# 1091
	$sites{'1091'}->{'name'}         = 'Aventiv Research Inc (Facility and Drug Shipment Address)';
	$sites{'1091'}->{'address'}      = '99 N. Brice Rd, Ste 210';
	$sites{'1091'}->{'postalCode'}   = 'OHIO 43213';
	$sites{'1091'}->{'city'}         = 'Columbus';
	$sites{'1091'}->{'investigator'} = 'Samir Arora';
	$sites{'1091'}->{'latitude'}     = '39.984484';
	$sites{'1091'}->{'longitude'}    = '-82.826839';
	# 1092
	$sites{'1092'}->{'name'}         = 'Sterling Research Group, Ltd.';
	$sites{'1092'}->{'address'}      = '375 Glenspring Dr, 2nd F1';
	$sites{'1092'}->{'postalCode'}   = 'OH 45246';
	$sites{'1092'}->{'city'}         = 'Cincinnati';
	$sites{'1092'}->{'investigator'} = 'Rajesh Davit';
	$sites{'1092'}->{'latitude'}     = '39.292321';
	$sites{'1092'}->{'longitude'}    = '-84.487138';
	# 1093
	$sites{'1093'}->{'name'}         = 'Meridian Clinical Research, LLC';
	$sites{'1093'}->{'address'}      = '4802 Sunnybrook Dr';
	$sites{'1093'}->{'postalCode'}   = 'IOWA 51106';
	$sites{'1093'}->{'city'}         = 'Sioux City';
	$sites{'1093'}->{'investigator'} = 'David Ensz';
	$sites{'1093'}->{'latitude'}     = '42.455354';
	$sites{'1093'}->{'longitude'}    = '-96.345013';
	# 1094
	$sites{'1094'}->{'name'}         = 'LinQ Research, LLC';
	$sites{'1094'}->{'address'}      = '11021 Shadow Creek Pkwy, Ste 102';
	$sites{'1094'}->{'postalCode'}   = 'TEXAS 77584';
	$sites{'1094'}->{'city'}         = 'Pearland';
	$sites{'1094'}->{'investigator'} = 'Murtaza Mussaji';
	$sites{'1094'}->{'latitude'}     = '29.582949';
	$sites{'1094'}->{'longitude'}    = '-95.387597';
	# 1095
	$sites{'1095'}->{'name'}         = 'Tekton Research, Inc.';
	$sites{'1095'}->{'address'}      = '4534 W Gate Blvd., Ste 110';
	$sites{'1095'}->{'postalCode'}   = 'TEXAS 78745';
	$sites{'1095'}->{'city'}         = 'Houston';
	$sites{'1095'}->{'investigator'} = 'Paul Pickrell';
	$sites{'1095'}->{'latitude'}     = '30.230984';
	$sites{'1095'}->{'longitude'}    = '-97.802824';
	# 1096
	$sites{'1096'}->{'name'}         = 'Dr Van Tran Family Practice, Hany H. Ahmed MD & Ventavia Research Group, LLC';
	$sites{'1096'}->{'address'}      = '1919 N Loop W, Ste 250';
	$sites{'1096'}->{'postalCode'}   = 'TX 77008';
	$sites{'1096'}->{'city'}         = 'Houston';
	$sites{'1096'}->{'investigator'} = 'Van Tran';
	$sites{'1096'}->{'latitude'}     = '29.810730';
	$sites{'1096'}->{'longitude'}    = '-95.434200';
	# 1097
	$sites{'1097'}->{'name'}         = 'Main Street Physician\'s Care';
	$sites{'1097'}->{'address'}      = '3600 Sea Moutain';
	$sites{'1097'}->{'postalCode'}   = 'South Carolina 29566';
	$sites{'1097'}->{'city'}         = 'Little River';
	$sites{'1097'}->{'investigator'} = 'Tom Christensen';
	$sites{'1097'}->{'latitude'}     = '33.868737';
	$sites{'1097'}->{'longitude'}    = '-78.671005';
	# 1098
	$sites{'1098'}->{'name'}         = 'SMS Clinical Research, LLC';
	$sites{'1098'}->{'address'}      = '1210 N Galloway Ave';
	$sites{'1098'}->{'postalCode'}   = 'TX 75149';
	$sites{'1098'}->{'city'}         = 'Mesquite';
	$sites{'1098'}->{'investigator'} = 'Salma Saiger';
	$sites{'1098'}->{'latitude'}     = '32.779964';
	$sites{'1098'}->{'longitude'}    = '-96.600121';
	# 1101
	$sites{'1101'}->{'name'}         = 'Methodist Physicians Clinic / CCT Research';
	$sites{'1101'}->{'address'}      = '350 W 23rd St';
	$sites{'1101'}->{'postalCode'}   = 'NE 68025';
	$sites{'1101'}->{'city'}         = 'Fremont';
	$sites{'1101'}->{'investigator'} = 'Thomas Wolf';
	$sites{'1101'}->{'latitude'}     = '41.451665';
	$sites{'1101'}->{'longitude'}    = '-96.500113';
	# 1107
	$sites{'1107'}->{'name'}         = 'Alliance for Multispecialty Research, LLC';
	$sites{'1107'}->{'address'}      = '100 Memorial Hospital Dr, Annex Bldg, Ste-3B';
	$sites{'1107'}->{'postalCode'}   = 'AL 36608';
	$sites{'1107'}->{'city'}         = 'Mobile';
	$sites{'1107'}->{'investigator'} = 'Harry Studdard';
	$sites{'1107'}->{'latitude'}     = '30.683890';
	$sites{'1107'}->{'longitude'}    = '-88.130755';
	# 1109
	$sites{'1109'}->{'name'}         = 'DeLand Clinical Research Unit';
	$sites{'1109'}->{'address'}      = '860 Peachwood Dr';
	$sites{'1109'}->{'postalCode'}   = 'FLORIDA 32720';
	$sites{'1109'}->{'city'}         = 'DeLand';
	$sites{'1109'}->{'investigator'} = 'Bruce Rankin';
	$sites{'1109'}->{'latitude'}     = '29.044612';
	$sites{'1109'}->{'longitude'}    = '-81.314699';
	# 1110
	$sites{'1110'}->{'name'}         = 'Alliance for Multispecialty Research, LLC-Miami';
	$sites{'1110'}->{'address'}      = '370 Minorca Ave, Miami-Dade County, Coral Gables Section';
	$sites{'1110'}->{'postalCode'}   = 'FLORIDA 33134';
	$sites{'1110'}->{'city'}         = 'Coral Gables';
	$sites{'1110'}->{'investigator'} = 'Jeffrey Rosen';
	$sites{'1110'}->{'latitude'}     = '25.753515';
	$sites{'1110'}->{'longitude'}    = '-80.262393';
	# 1111
	$sites{'1111'}->{'name'}         = 'Fleming Island Center for Clinical Research';
	$sites{'1111'}->{'address'}      = '1679 Eagle Harbor Pkwy, Ste D';
	$sites{'1111'}->{'postalCode'}   = 'FL 32003';
	$sites{'1111'}->{'city'}         = 'Fleming Island';
	$sites{'1111'}->{'investigator'} = 'Michael Stephens';
	$sites{'1111'}->{'latitude'}     = '30.100353';
	$sites{'1111'}->{'longitude'}    = '-81.704563';
	# 1112
	$sites{'1112'}->{'name'}         = 'Clinical Research Atlanta';
	$sites{'1112'}->{'address'}      = '175 Country Club Dr, Bldg 100, Ste A';
	$sites{'1112'}->{'postalCode'}   = 'GA 30281';
	$sites{'1112'}->{'city'}         = 'Stockbridge';
	$sites{'1112'}->{'investigator'} = 'Nathan Segall';
	$sites{'1112'}->{'latitude'}     = '33.505802';
	$sites{'1112'}->{'longitude'}    = '-84.226060';
	# 1114
	$sites{'1114'}->{'name'}         = 'Alliance for Multispeciality Research, LLC';
	$sites{'1114'}->{'address'}      = '700 Medical Center Dr, Ste 110';
	$sites{'1114'}->{'postalCode'}   = 'KANSAS 67114';
	$sites{'1114'}->{'city'}         = 'Newton';
	$sites{'1114'}->{'investigator'} = 'Richard Glover';
	$sites{'1114'}->{'latitude'}     = '38.022490';
	$sites{'1114'}->{'longitude'}    = '-97.332772';
	# 1116
	$sites{'1116'}->{'name'}         = 'MedPharmics, LLC';
	$sites{'1116'}->{'address'}      = '15190 Community Rd., Ste 350';
	$sites{'1116'}->{'postalCode'}   = 'MISSISSIPI 39503';
	$sites{'1116'}->{'city'}         = 'Gulfport';
	$sites{'1116'}->{'investigator'} = 'Paul Matherne';
	$sites{'1116'}->{'latitude'}     = '30.443989';
	$sites{'1116'}->{'longitude'}    = '-89.093605';
	# 1117
	$sites{'1117'}->{'name'}         = 'Sundance Clinical Research, LLC';
	$sites{'1117'}->{'address'}      = '711 Old Ballas Rd, Ste 105';
	$sites{'1117'}->{'postalCode'}   = 'MO 63141';
	$sites{'1117'}->{'city'}         = 'St Louis';
	$sites{'1117'}->{'investigator'} = 'Larkin Wadsworth';
	$sites{'1117'}->{'latitude'}     = '38.668863';
	$sites{'1117'}->{'longitude'}    = '-90.438865';
	# 1118
	$sites{'1118'}->{'name'}         = 'Meridian Clinical Research, LLC';
	$sites{'1118'}->{'address'}      = '1290 Uppr Frnt St';
	$sites{'1118'}->{'postalCode'}   = 'NEW YORK 13901';
	$sites{'1118'}->{'city'}         = 'Binghamton';
	$sites{'1118'}->{'investigator'} = 'Frank Eder';
	$sites{'1118'}->{'latitude'}     = '42.160032';
	$sites{'1118'}->{'longitude'}    = '-75.893706';
	# 1120
	$sites{'1120'}->{'name'}         = 'Meridian Clinical Research, LLC';
	$sites{'1120'}->{'address'}      = '340 Eisenhower Dr, Ste 1200';
	$sites{'1120'}->{'postalCode'}   = 'GA 31406';
	$sites{'1120'}->{'city'}         = 'Savannah';
	$sites{'1120'}->{'investigator'} = 'Paul Bradley';
	$sites{'1120'}->{'latitude'}     = '32.008920';
	$sites{'1120'}->{'longitude'}    = '-81.106783';
	# 1121
	$sites{'1121'}->{'name'}         = 'Optimal Research, LLC';
	$sites{'1121'}->{'address'}      = '4911 N. Executive Dr, 2nd Fl';
	$sites{'1121'}->{'postalCode'}   = 'ILLINOIS 61614';
	$sites{'1121'}->{'city'}         = 'Peoria';
	$sites{'1121'}->{'investigator'} = 'Daniel Brune';
	$sites{'1121'}->{'latitude'}     = '40.747241';
	$sites{'1121'}->{'longitude'}    = '-89.608416';
	# 1122
	$sites{'1122'}->{'name'}         = 'VA Northeast Ohio Healthcare System';
	$sites{'1122'}->{'address'}      = '10701 E Blvd.';
	$sites{'1122'}->{'postalCode'}   = 'OHIO 44106';
	$sites{'1122'}->{'city'}         = 'Cleveland';
	$sites{'1122'}->{'investigator'} = 'Curtis Donskey';
	$sites{'1122'}->{'latitude'}     = '41.514240';
	$sites{'1122'}->{'longitude'}    = '-81.613110';
	# 1123
	$sites{'1123'}->{'name'}         = 'Meridian Clinical Research, LLC';
	$sites{'1123'}->{'address'}      = '3319 N 107th St.';
	$sites{'1123'}->{'postalCode'}   = 'NEBRASKA 68134';
	$sites{'1123'}->{'city'}         = 'Omaha';
	$sites{'1123'}->{'investigator'} = 'Brandon Essink';
	$sites{'1123'}->{'latitude'}     = '41.289274';
	$sites{'1123'}->{'longitude'}    = '-96.079164';
	# 1124
	$sites{'1124'}->{'name'}         = 'Omega Medical Research';
	$sites{'1124'}->{'address'}      = '400 Bald Hill Rd';
	$sites{'1124'}->{'postalCode'}   = 'RHODE ISLAND 02886';
	$sites{'1124'}->{'city'}         = 'Warwick';
	$sites{'1124'}->{'investigator'} = 'David Fried';
	$sites{'1124'}->{'latitude'}     = '41.724736';
	$sites{'1124'}->{'longitude'}    = '-71.478541';
	# 1125
	$sites{'1125'}->{'name'}         = 'Meridian Clinical Research, LLC';
	$sites{'1125'}->{'address'}      = '1410 N 13th St., Ste 5';
	$sites{'1125'}->{'postalCode'}   = 'NE 68701';
	$sites{'1125'}->{'city'}         = 'Norfolk';
	$sites{'1125'}->{'investigator'} = 'Charles Harper';
	$sites{'1125'}->{'latitude'}     = '42.048817';
	$sites{'1125'}->{'longitude'}    = '-97.426160';
	# 1126
	$sites{'1126'}->{'name'}         = 'Kaiser Permanente Sacramento';
	$sites{'1126'}->{'address'}      = '1650 Response Rd';
	$sites{'1126'}->{'postalCode'}   = 'CA 95815';
	$sites{'1126'}->{'city'}         = 'Sacramento';
	$sites{'1126'}->{'investigator'} = 'Nicola Klein';
	$sites{'1126'}->{'latitude'}     = '37.662357';
	$sites{'1126'}->{'longitude'}    = '-97.245145';
	# 1127
	$sites{'1127'}->{'name'}         = 'Alliance for Multispecialty Research, LLC';
	$sites{'1127'}->{'address'}      = '1709 S Rock Rd';
	$sites{'1127'}->{'postalCode'}   = 'KS 67207';
	$sites{'1127'}->{'city'}         = 'Wichita';
	$sites{'1127'}->{'investigator'} = 'Tracy Klein';
	$sites{'1127'}->{'latitude'}     = '38.595276';
	$sites{'1127'}->{'longitude'}    = '-121.429798';
	# 1128
	$sites{'1128'}->{'name'}         = 'Ventavia Research Group, LLC';
	$sites{'1128'}->{'address'}      = '1307 8th Ave, Ste 202 & Ste M1';
	$sites{'1128'}->{'postalCode'}   = 'TX 76104';
	$sites{'1128'}->{'city'}         = 'Fort Worth';
	$sites{'1128'}->{'investigator'} = 'Mark Koch';
	$sites{'1128'}->{'latitude'}     = '32.730420';
	$sites{'1128'}->{'longitude'}    = '-97.342842';
	# 1129
	$sites{'1129'}->{'name'}         = 'Jacksonville Center for Clinical Research';
	$sites{'1129'}->{'address'}      = '4085 University Blvd, Ste 1';
	$sites{'1129'}->{'postalCode'}   = 'FL 32216';
	$sites{'1129'}->{'city'}         = 'Jacksonville';
	$sites{'1129'}->{'investigator'} = 'Michael Koren';
	$sites{'1129'}->{'latitude'}     = '30.283314';
	$sites{'1129'}->{'longitude'}    = '-81.601679';
	# 1130
	$sites{'1130'}->{'name'}         = 'Kaiser Permanente Northwest-Center for Health';
	$sites{'1130'}->{'address'}      = '3800 N Interstate Ave';
	$sites{'1130'}->{'postalCode'}   = 'OR 97227';
	$sites{'1130'}->{'city'}         = 'Portland';
	$sites{'1130'}->{'investigator'} = 'Stephen Fortmann';
	$sites{'1130'}->{'latitude'}     = '45.550319';
	$sites{'1130'}->{'longitude'}    = '-122.680840';
	# 1131
	$sites{'1131'}->{'name'}         = 'PriMED Clinical Research';
	$sites{'1131'}->{'address'}      = '948 Patterson Rd';
	$sites{'1131'}->{'postalCode'}   = 'OHIO 45419';
	$sites{'1131'}->{'city'}         = 'Dayton';
	$sites{'1131'}->{'investigator'} = 'William Randall';
	$sites{'1131'}->{'latitude'}     = '39.724205';
	$sites{'1131'}->{'longitude'}    = '-84.153467';
	# 1133
	$sites{'1133'}->{'name'}         = 'Research Centers of America';
	$sites{'1133'}->{'address'}      = '7261 Sheridan St, Suites 210, 215, 310';
	$sites{'1133'}->{'postalCode'}   = 'FLORIDA 33024';
	$sites{'1133'}->{'city'}         = 'Hollywood';
	$sites{'1133'}->{'investigator'} = 'Howard Schwartz';
	$sites{'1133'}->{'latitude'}     = '26.032258';
	$sites{'1133'}->{'longitude'}    = '-80.234138';
	# 1134
	$sites{'1134'}->{'name'}         = 'PMG Research of Winston-Salem, LLC';
	$sites{'1134'}->{'address'}      = '1901 S. Hawthorne Rd, Ste 306';
	$sites{'1134'}->{'postalCode'}   = 'NC 27103';
	$sites{'1134'}->{'city'}         = 'Winston-Salem';
	$sites{'1134'}->{'investigator'} = 'Jonathan Wilson';
	$sites{'1134'}->{'latitude'}     = '36.077265';
	$sites{'1134'}->{'longitude'}    = '-80.295588';
	# 1135
	$sites{'1135'}->{'name'}         = 'Anaheim Clinical Trials, LLC';
	$sites{'1135'}->{'address'}      = '1085 N. Harbor Blvd.';
	$sites{'1135'}->{'postalCode'}   = 'CA 92801';
	$sites{'1135'}->{'city'}         = 'Anaheim';
	$sites{'1135'}->{'investigator'} = 'Peter Winkle';
	$sites{'1135'}->{'latitude'}     = '33.850280';
	$sites{'1135'}->{'longitude'}    = '-117.924733';
	# 1136
	$sites{'1136'}->{'name'}         = 'Wake Research-Clinical Center of Nevada, LLC';
	$sites{'1136'}->{'address'}      = '1022E Sahara Ave';
	$sites{'1136'}->{'postalCode'}   = 'NEVADA 89104';
	$sites{'1136'}->{'city'}         = 'Las Vegas';
	$sites{'1136'}->{'investigator'} = 'Michael Levin';
	$sites{'1136'}->{'latitude'}     = '36.145827';
	$sites{'1136'}->{'longitude'}    = '-115.140502';
	# 1139
	$sites{'1139'}->{'name'}         = 'Duke Vaccine and Trials Unit';
	$sites{'1139'}->{'address'}      = '2608 Erwin Rd, Ste 210';
	$sites{'1139'}->{'postalCode'}   = 'NORTH CAROLINA 27705';
	$sites{'1139'}->{'city'}         = 'Durham';
	$sites{'1139'}->{'investigator'} = 'Emmanuel Walter';
	$sites{'1139'}->{'latitude'}     = '36.008967';
	$sites{'1139'}->{'longitude'}    = '-78.944857';
	# 1140
	$sites{'1140'}->{'name'}         = 'SUNY Upstate Medical University';
	$sites{'1140'}->{'address'}      = '505 Irving Ave, Clinical Research Unit';
	$sites{'1140'}->{'postalCode'}   = 'NY 13210';
	$sites{'1140'}->{'city'}         = 'Syracuse';
	$sites{'1140'}->{'investigator'} = 'Stephen Thomas';
	$sites{'1140'}->{'latitude'}     = '43.044949';
	$sites{'1140'}->{'longitude'}    = '-76.136962';
	# 1141
	$sites{'1141'}->{'name'}         = 'University of Iowa Hospitals & Clinics';
	$sites{'1141'}->{'address'}      = '200 Hawkins Dr';
	$sites{'1141'}->{'postalCode'}   = 'IA 52242';
	$sites{'1141'}->{'city'}         = 'Iowa City';
	$sites{'1141'}->{'investigator'} = 'Patricia Winokur';
	$sites{'1141'}->{'latitude'}     = '41.660436';
	$sites{'1141'}->{'longitude'}    = '-91.548543';
	# 1142
	$sites{'1142'}->{'name'}         = 'University of Texas Medical Branch';
	$sites{'1142'}->{'address'}      = 'Pavilion, 400 Harborside Dr, Ste 126';
	$sites{'1142'}->{'postalCode'}   = 'TEXAS 77555';
	$sites{'1142'}->{'city'}         = 'Galveston';
	$sites{'1142'}->{'investigator'} = 'Richard Rupp';
	$sites{'1142'}->{'latitude'}     = '29.314075';
	$sites{'1142'}->{'longitude'}    = '-94.774518';
	# 1145
	$sites{'1145'}->{'name'}         = 'Center for Immunization Research Inpatient Unit Johns Hopkins Bayview Medical Center';
	$sites{'1145'}->{'address'}      = '301 Mason Lord Dr, 4300';
	$sites{'1145'}->{'postalCode'}   = 'MD 21224';
	$sites{'1145'}->{'city'}         = 'Baltimore';
	$sites{'1145'}->{'investigator'} = 'Kawsar Talaat';
	$sites{'1145'}->{'latitude'}     = '39.291280';
	$sites{'1145'}->{'longitude'}    = '-76.545799';
	# 1146
	$sites{'1146'}->{'name'}         = 'Amici Clinical Research';
	$sites{'1146'}->{'address'}      = '34 E Somerset St';
	$sites{'1146'}->{'postalCode'}   = 'NJ 08869';
	$sites{'1146'}->{'city'}         = 'Rajitan';
	$sites{'1146'}->{'investigator'} = 'Robert Falcone';
	$sites{'1146'}->{'latitude'}     = '40.568084';
	$sites{'1146'}->{'longitude'}    = '-74.630641';
	# 1147
	$sites{'1147'}->{'name'}         = 'Ochsner Clinic Foundation';
	$sites{'1147'}->{'address'}      = '1514 Jefferson Hwy';
	$sites{'1147'}->{'postalCode'}   = 'LA 70121';
	$sites{'1147'}->{'city'}         = 'New Orleans';
	$sites{'1147'}->{'investigator'} = 'Julia Garcia-Diaz';
	$sites{'1147'}->{'latitude'}     = '29.962430';
	$sites{'1147'}->{'longitude'}    = '-90.145600';
	# 1149
	$sites{'1149'}->{'name'}         = 'Collaborative Neuroscience Research, LLC';
	$sites{'1149'}->{'address'}      = '12772 Valley View St, Ste 3';
	$sites{'1149'}->{'postalCode'}   = 'CA 92845';
	$sites{'1149'}->{'city'}         = 'Garden Grove';
	$sites{'1149'}->{'investigator'} = 'Steven Reynolds';
	$sites{'1149'}->{'latitude'}     = '33.777543';
	$sites{'1149'}->{'longitude'}    = '-118.034075';
	# 1150
	$sites{'1150'}->{'name'}         = 'Senders Pediatrics';
	$sites{'1150'}->{'address'}      = '2054 S Green Rd';
	$sites{'1150'}->{'postalCode'}   = 'OH 44121';
	$sites{'1150'}->{'city'}         = 'South Euclid';
	$sites{'1150'}->{'investigator'} = 'Shelly Senders';
	$sites{'1150'}->{'latitude'}     = '41.504194';
	$sites{'1150'}->{'longitude'}    = '-81.519490';
	# 1152
	$sites{'1152'}->{'name'}         = 'California Research Foundation';
	$sites{'1152'}->{'address'}      = '4180 Ruffin Rd, Ste 255';
	$sites{'1152'}->{'postalCode'}   = 'CALIFORNIA 92123-1881';
	$sites{'1152'}->{'city'}         = 'San Diego';
	$sites{'1152'}->{'investigator'} = 'Donald Branson';
	$sites{'1152'}->{'latitude'}     = '32.817426';
	$sites{'1152'}->{'longitude'}    = '-117.124983';
	# 1156
	$sites{'1156'}->{'name'}         = 'Acevedo Clinical Research Associates';
	$sites{'1156'}->{'address'}      = '2400 Nw 54th St';
	$sites{'1156'}->{'postalCode'}   = 'FL 33142';
	$sites{'1156'}->{'city'}         = 'Miami';
	$sites{'1156'}->{'investigator'} = 'Hector Rodriguez';
	$sites{'1156'}->{'latitude'}     = '25.823990';
	$sites{'1156'}->{'longitude'}    = '-80.237163';
	# 1157
	$sites{'1157'}->{'name'}         = 'Paradigm Clinical Research Center';
	$sites{'1157'}->{'address'}      = '3652 Eureka Way';
	$sites{'1157'}->{'postalCode'}   = 'CA 96001';
	$sites{'1157'}->{'city'}         = 'Redding';
	$sites{'1157'}->{'investigator'} = 'Jamshid Saleh';
	$sites{'1157'}->{'latitude'}     = '40.584164';
	$sites{'1157'}->{'longitude'}    = '-122.425566';
	# 1161
	$sites{'1161'}->{'name'}         = 'Benchmark Research';
	$sites{'1161'}->{'address'}      = '3605 Executive Dr';
	$sites{'1161'}->{'postalCode'}   = 'TX 76904';
	$sites{'1161'}->{'city'}         = 'San Angelo';
	$sites{'1161'}->{'investigator'} = 'Darrel Herrington';
	$sites{'1161'}->{'latitude'}     = '31.416111';
	$sites{'1161'}->{'longitude'}    = '-100.470492';
	# 1162
	$sites{'1162'}->{'name'}         = 'Atlanta Center for Medical Research';
	$sites{'1162'}->{'address'}      = '501 Fairburn Rd SW';
	$sites{'1162'}->{'postalCode'}   = 'Georgia 30331';
	$sites{'1162'}->{'city'}         = 'Atlanta';
	$sites{'1162'}->{'investigator'} = 'Robert Riesenberg';
	$sites{'1162'}->{'latitude'}     = '33.740088';
	$sites{'1162'}->{'longitude'}    = '-84.512626';
	# 1163
	$sites{'1163'}->{'name'}         = 'Benchmark Research';
	$sites{'1163'}->{'address'}      = '4517 Veterans Memorial Blvd';
	$sites{'1163'}->{'postalCode'}   = 'Louisiana 70006';
	$sites{'1163'}->{'city'}         = 'Metairie';
	$sites{'1163'}->{'investigator'} = 'George Bauer';
	$sites{'1163'}->{'latitude'}     = '30.006103';
	$sites{'1163'}->{'longitude'}    = '-90.184251';
	# 1166
	$sites{'1166'}->{'name'}         = 'Rapid Medical Research, Inc.';
	$sites{'1166'}->{'address'}      = '3619 Park E Dr, Ste 300';
	$sites{'1166'}->{'postalCode'}   = 'OH 44122';
	$sites{'1166'}->{'city'}         = 'Cleveland';
	$sites{'1166'}->{'investigator'} = 'Mary Beth Manning';
	$sites{'1166'}->{'latitude'}     = '41.461777';
	$sites{'1166'}->{'longitude'}    = '-81.493970';
	# 1167
	$sites{'1167'}->{'name'}         = 'Holston Medical Group';
	$sites{'1167'}->{'address'}      = '105 W Stone Dr, 3rd Fl, Ste 3B';
	$sites{'1167'}->{'postalCode'}   = 'TN 37660';
	$sites{'1167'}->{'city'}         = 'Kingsport';
	$sites{'1167'}->{'investigator'} = 'Emily Morawski';
	$sites{'1167'}->{'latitude'}     = '36.557416';
	$sites{'1167'}->{'longitude'}    = '-82.552999';
	# 1168
	$sites{'1168'}->{'name'}         = 'Lynn Institute of Norman';
	$sites{'1168'}->{'address'}      = '630 24th Ave Sw.';
	$sites{'1168'}->{'postalCode'}   = 'OKLAHOMA 73069';
	$sites{'1168'}->{'city'}         = 'Norman';
	$sites{'1168'}->{'investigator'} = 'Steven Cox';
	$sites{'1168'}->{'latitude'}     = '35.209973';
	$sites{'1168'}->{'longitude'}    = '-97.476766';
	# 1169
	$sites{'1169'}->{'name'}         = 'Lehigh Valley Health Network / Network Office of Research and Innovation';
	$sites{'1169'}->{'address'}      = '17th & Chew Streets';
	$sites{'1169'}->{'postalCode'}   = 'PA 18102';
	$sites{'1169'}->{'city'}         = 'Allentown';
	$sites{'1169'}->{'investigator'} = 'Joseph Yozviak';
	$sites{'1169'}->{'latitude'}     = '40.600758';
	$sites{'1169'}->{'longitude'}    = '-75.494202';
	# 1170
	$sites{'1170'}->{'name'}         = 'North Texas Infectious Deseases Consultants, P.A.';
	$sites{'1170'}->{'address'}      = '3409 Worth St, Ste 710, 725, 740';
	$sites{'1170'}->{'postalCode'}   = 'TEXAS 75246';
	$sites{'1170'}->{'city'}         = 'Dallas';
	$sites{'1170'}->{'investigator'} = 'Mezgebe Berhe';
	$sites{'1170'}->{'latitude'}     = '32.788375';
	$sites{'1170'}->{'longitude'}    = '-96.779399';
	# 1171
	$sites{'1171'}->{'name'}         = 'DM Clinical Research';
	$sites{'1171'}->{'address'}      = '13406 Medical Complex Dr, Ste 53';
	$sites{'1171'}->{'postalCode'}   = 'TX 77375';
	$sites{'1171'}->{'city'}         = 'Tomball';
	$sites{'1171'}->{'investigator'} = 'Earl Martin';
	$sites{'1171'}->{'latitude'}     = '30.084754';
	$sites{'1171'}->{'longitude'}    = '-95.623484';
	# 1174
	$sites{'1174'}->{'name'}         = 'Infectious Diseases Physicians, LLC';
	$sites{'1174'}->{'address'}      = '3289 Woodburn Rd, Ste 200';
	$sites{'1174'}->{'postalCode'}   = 'VA 22003';
	$sites{'1174'}->{'city'}         = 'Annandale';
	$sites{'1174'}->{'investigator'} = 'Donald Poretz';
	$sites{'1174'}->{'latitude'}     = '38.854249';
	$sites{'1174'}->{'longitude'}    = '-77.223548';
	# 1177
	$sites{'1177'}->{'name'}         = 'East-West Medical Reseach Institute';
	$sites{'1177'}->{'address'}      = '1585 Kapiolani Blvd, Ste 1500';
	$sites{'1177'}->{'postalCode'}   = 'HI 96814';
	$sites{'1177'}->{'city'}         = 'Honolulu';
	$sites{'1177'}->{'investigator'} = 'David Fitz-Patrick';
	$sites{'1177'}->{'latitude'}     = '21.291175';
	$sites{'1177'}->{'longitude'}    = '-157.840296';
	# 1178
	$sites{'1178'}->{'name'}         = 'Clinical Research Associates, Inc.';
	$sites{'1178'}->{'address'}      = '1500 Church St, Ste 100';
	$sites{'1178'}->{'postalCode'}   = 'TEXAS 75246';
	$sites{'1178'}->{'city'}         = 'Dallas';
	$sites{'1178'}->{'investigator'} = 'Stephan Sharp';
	$sites{'1178'}->{'latitude'}     = '32.750371';
	$sites{'1178'}->{'longitude'}    = '-96.803811';
	# 1179
	$sites{'1179'}->{'name'}         = 'Michigan Center for Medical Research';
	$sites{'1179'}->{'address'}      = '30160 Orchard Lake Rd';
	$sites{'1179'}->{'postalCode'}   = 'MI 48334';
	$sites{'1179'}->{'city'}         = 'Farmington Hills';
	$sites{'1179'}->{'investigator'} = 'Steven Katzman';
	$sites{'1179'}->{'latitude'}     = '42.519643';
	$sites{'1179'}->{'longitude'}    = '-83.359298';
	# 1185
	$sites{'1185'}->{'name'}         = 'Universitatsklinikum Hamburg-Eppendorf';
	$sites{'1185'}->{'address'}      = 'Bernhard-Nocht-Str 74';
	$sites{'1185'}->{'postalCode'}   = '20359';
	$sites{'1185'}->{'city'}         = 'Hamburg';
	$sites{'1185'}->{'investigator'} = 'Marylyn Addo';
	$sites{'1185'}->{'latitude'}     = '53.547077';
	$sites{'1185'}->{'longitude'}    = '9.964825';
	# 1194
	$sites{'1194'}->{'name'}         = 'IKF Pneumologie GmbH & Co KG';
	$sites{'1194'}->{'address'}      = 'Institut für klinische Forschung';
	$sites{'1194'}->{'postalCode'}   = '60596';
	$sites{'1194'}->{'city'}         = 'Frankfurt am Main';
	$sites{'1194'}->{'investigator'} = 'Steven Katzman';
	$sites{'1194'}->{'latitude'}     = '50.100141';
	$sites{'1194'}->{'longitude'}    = '8.668858';
	# 1195
	$sites{'1195'}->{'name'}         = 'Medizentrum Essen Borbeck';
	$sites{'1195'}->{'address'}      = 'Huelsmannstrasse 6';
	$sites{'1195'}->{'postalCode'}   = '45355';
	$sites{'1195'}->{'city'}         = 'Essen';
	$sites{'1195'}->{'investigator'} = 'Axel Schaefer';
	$sites{'1195'}->{'latitude'}     = '51.475626';
	$sites{'1195'}->{'longitude'}    = '6.951541';
	# 1197
	$sites{'1197'}->{'name'}         = 'Studienzentrum Brinkum Dr. Lars Pohlmeier und Torsten Drescher';
	$sites{'1197'}->{'address'}      = 'Melcherstaette 7';
	$sites{'1197'}->{'postalCode'}   = '28816';
	$sites{'1197'}->{'city'}         = 'Stuhr';
	$sites{'1197'}->{'investigator'} = 'Matthias Luttermann';
	$sites{'1197'}->{'latitude'}     = '53.008653';
	$sites{'1197'}->{'longitude'}    = '8.783205';
	# 1202
	$sites{'1202'}->{'name'}         = 'CRS Clinical Research Services Mannheim GmbH';
	$sites{'1202'}->{'address'}      = 'Grenadierstr. 1';
	$sites{'1202'}->{'postalCode'}   = '68167';
	$sites{'1202'}->{'city'}         = 'Mannheim';
	$sites{'1202'}->{'investigator'} = 'Armin Schultz';
	$sites{'1202'}->{'latitude'}     = '49.500255';
	$sites{'1202'}->{'longitude'}    = '8.488605';
	# 1203
	$sites{'1203'}->{'name'}         = 'CRS Clinical Research Services Berlin GmbH';
	$sites{'1203'}->{'address'}      = 'Sellerstr. 31';
	$sites{'1203'}->{'postalCode'}   = '13353';
	$sites{'1203'}->{'city'}         = 'Berlin';
	$sites{'1203'}->{'investigator'} = 'Sybille Baumann';
	$sites{'1203'}->{'latitude'}     = '52.539590';
	$sites{'1203'}->{'longitude'}    = '13.370117';
	# 1204
	$sites{'1204'}->{'name'}         = 'Icahn School of Medicine at Mount Sinai';
	$sites{'1204'}->{'address'}      = '17 E 102nd st, 8th fl';
	$sites{'1204'}->{'postalCode'}   = 'NY 10029';
	$sites{'1204'}->{'city'}         = 'New York';
	$sites{'1204'}->{'investigator'} = 'Judith Aberg';
	$sites{'1204'}->{'latitude'}     = '40.791404';
	$sites{'1204'}->{'longitude'}    = '-73.952085';
	# 1205
	$sites{'1205'}->{'name'}         = 'Hacettepe Universitesi Tip Fakultesi';
	$sites{'1205'}->{'address'}      = 'Anabilim Dali, Sihhiye';
	$sites{'1205'}->{'postalCode'}   = '06230';
	$sites{'1205'}->{'city'}         = 'Ankara';
	$sites{'1205'}->{'investigator'} = 'Serhat Unal';
	$sites{'1205'}->{'latitude'}     = '39.931674';
	$sites{'1205'}->{'longitude'}    = '32.863173';
	# 1207
	$sites{'1207'}->{'name'}         = 'Ankara Universitesi Tip Fakultesi, Ibni Sina Hastanesi';
	$sites{'1207'}->{'address'}      = 'Anabilim Dali';
	$sites{'1207'}->{'postalCode'}   = '06230';
	$sites{'1207'}->{'city'}         = 'Ankara';
	$sites{'1207'}->{'investigator'} = 'Ismail Balik';
	$sites{'1207'}->{'latitude'}     = '39.933943';
	$sites{'1207'}->{'longitude'}    = '32.882137';
	# 1208
	$sites{'1208'}->{'name'}         = 'Acibadem Atakent Hastanesi, Enfeksiyon Hastaliklari ye Klinik Mikrobiyoloji';
	$sites{'1208'}->{'address'}      = 'Birimi, Kucukcekmece';
	$sites{'1208'}->{'postalCode'}   = '34303';
	$sites{'1208'}->{'city'}         = 'Istanbul';
	$sites{'1208'}->{'investigator'} = 'Iflihar Koksal';
	$sites{'1208'}->{'latitude'}     = '41.034447';
	$sites{'1208'}->{'longitude'}    = '28.778700';
	# 1209
	$sites{'1209'}->{'name'}         = 'Istanbul Yedikule Gogus Hastaliklari ve Gogus';
	$sites{'1209'}->{'address'}      = 'Zeytinburnu';
	$sites{'1209'}->{'postalCode'}   = '34020';
	$sites{'1209'}->{'city'}         = 'Istanbul';
	$sites{'1209'}->{'investigator'} = 'Sedat Altin';
	$sites{'1209'}->{'latitude'}     = '41.001984';
	$sites{'1209'}->{'longitude'}    = '28.915308';
	# 1210
	$sites{'1210'}->{'name'}         = 'Medipol Mega Uniyersite Hastanesi';
	$sites{'1210'}->{'address'}      = 'Bagcilar';
	$sites{'1210'}->{'postalCode'}   = '34214';
	$sites{'1210'}->{'city'}         = 'Istanbul';
	$sites{'1210'}->{'investigator'} = 'Ali Mert';
	$sites{'1210'}->{'latitude'}     = '41.058056';
	$sites{'1210'}->{'longitude'}    = '28.842730';
	# 1212
	$sites{'1212'}->{'name'}         = 'Sakarya Universitesi Egitim ye Arastirma';
	$sites{'1212'}->{'address'}      = 'Hastanesi, Adapazari';
	$sites{'1212'}->{'postalCode'}   = '54100';
	$sites{'1212'}->{'city'}         = 'Sakarya';
	$sites{'1212'}->{'investigator'} = 'Oguz Karabay';
	$sites{'1212'}->{'latitude'}     = '40.756266';
	$sites{'1212'}->{'longitude'}    = '30.390759';
	# 1213
	$sites{'1213'}->{'name'}         = 'Istanbul Universitesi-Cerrahpasa, Cerrahpasa Tip Fakultesi';
	$sites{'1213'}->{'address'}      = 'Enfeksiyon Hastaliklari ve Klinik Mikrobiyoloji, Anabilim Dali, Fatih';
	$sites{'1213'}->{'postalCode'}   = '34098';
	$sites{'1213'}->{'city'}         = 'Istanbul';
	$sites{'1213'}->{'investigator'} = 'Omer Tabak';
	$sites{'1213'}->{'latitude'}     = '41.004328';
	$sites{'1213'}->{'longitude'}    = '28.939809';
	# 1214
	$sites{'1214'}->{'name'}         = 'Istanbul Universitesi Istanbul Tip Fakultesi';
	$sites{'1214'}->{'address'}      = 'Enfeksiyon Hastaliklari ve Klutik Mikrobiyoloji Anabilim Dali Fatih';
	$sites{'1214'}->{'postalCode'}   = '34093';
	$sites{'1214'}->{'city'}         = 'Istanbul';
	$sites{'1214'}->{'investigator'} = 'Serap Simsek-Yavuz';
	$sites{'1214'}->{'latitude'}     = '41.004526';
	$sites{'1214'}->{'longitude'}    = '28.940009';
	# 1217
	$sites{'1217'}->{'name'}         = 'Kocaeli Universitesi Tip Fakultesi';
	$sites{'1217'}->{'address'}      = 'Enfeksiyon Hastaliklari ve Klinik Mikrobiyoloji Anabilim Dali Umuttepe';
	$sites{'1217'}->{'postalCode'}   = '41380';
	$sites{'1217'}->{'city'}         = 'Kocaeli';
	$sites{'1217'}->{'investigator'} = 'Sila Akhan';
	$sites{'1217'}->{'latitude'}     = '40.824714';
	$sites{'1217'}->{'longitude'}    = '29.919205';
	# 1218
	$sites{'1218'}->{'name'}         = 'Johns Hopkins Center for American Indian Health';
	$sites{'1218'}->{'address'}      = '308 Kuper St.';
	$sites{'1218'}->{'postalCode'}   = '41380';
	$sites{'1218'}->{'city'}         = 'Whiteriver';
	$sites{'1218'}->{'investigator'} = 'Laura Hammitt';
	$sites{'1218'}->{'latitude'}     = '33.878486';
	$sites{'1218'}->{'longitude'}    = '-109.961128';
	# 1219
	$sites{'1219'}->{'name'}         = 'Johns Hopkins Center for American Indian Health';
	$sites{'1219'}->{'address'}      = 'US Hwy 191 and Hospital Rd';
	$sites{'1219'}->{'postalCode'}   = '86503';
	$sites{'1219'}->{'city'}         = 'Chinle';
	$sites{'1219'}->{'investigator'} = 'Laura Hammitt';
	$sites{'1219'}->{'latitude'}     = '36.152499';
	$sites{'1219'}->{'longitude'}    = '-109.556408';
	# 1220
	$sites{'1220'}->{'name'}         = 'Northern Navajo Medical Center';
	$sites{'1220'}->{'address'}      = 'US Hwy 491 N';
	$sites{'1220'}->{'postalCode'}   = 'NEW MEXICO 87420';
	$sites{'1220'}->{'city'}         = 'Shiprock';
	$sites{'1220'}->{'investigator'} = 'Laura Hammitt';
	$sites{'1220'}->{'latitude'}     = '36.804719';
	$sites{'1220'}->{'longitude'}    = '-108.691378';
	# 1221
	$sites{'1221'}->{'name'}         = 'Gallup Indian Medical Center';
	$sites{'1221'}->{'address'}      = '516 E Nizhoni Blvd';
	$sites{'1221'}->{'postalCode'}   = 'New Mexico 87301';
	$sites{'1221'}->{'city'}         = 'Gallup';
	$sites{'1221'}->{'investigator'} = 'Laura Hammitt';
	$sites{'1221'}->{'latitude'}     = '35.508026';
	$sites{'1221'}->{'longitude'}    = '-108.729960';
	# 1223
	$sites{'1223'}->{'name'}         = 'Yale Center for Clinical Investigations';
	$sites{'1223'}->{'address'}      = '2 Church St S, Ste 114';
	$sites{'1223'}->{'postalCode'}   = 'CT 06510';
	$sites{'1223'}->{'city'}         = 'New Haven';
	$sites{'1223'}->{'investigator'} = 'Onyema Ogbuagu';
	$sites{'1223'}->{'latitude'}     = '41.301948';
	$sites{'1223'}->{'longitude'}    = '-72.930261';
	# 1224
	$sites{'1224'}->{'name'}         = 'Lynn Institute of Denver';
	$sites{'1224'}->{'address'}      = '1411 S. Potomac St, Ste 420';
	$sites{'1224'}->{'postalCode'}   = 'CO 80012';
	$sites{'1224'}->{'city'}         = 'Aurora';
	$sites{'1224'}->{'investigator'} = 'Larry Odekirk';
	$sites{'1224'}->{'latitude'}     = '39.691116';
	$sites{'1224'}->{'longitude'}    = '-104.833078';
	# 1226
	$sites{'1226'}->{'name'}         = 'CEPIC - Centro Paulista de Investigacao Clinica e Servicos Medicos Ltda (Casa Blanca)';
	$sites{'1226'}->{'address'}      = 'Rua Moreira e Costa, 342 - Ipiranga';
	$sites{'1226'}->{'postalCode'}   = 'SP 04266-010';
	$sites{'1226'}->{'city'}         = 'Sao Paulo';
	$sites{'1226'}->{'investigator'} = 'Cristiano Zerbini';
	$sites{'1226'}->{'latitude'}     = '-23.589737';
	$sites{'1226'}->{'longitude'}    = '-46.611078';
	# 1229
	$sites{'1229'}->{'name'}         = 'Newtown Clinical Research Centre';
	$sites{'1229'}->{'address'}      = '104 Jeppe Street, Newtown, Suite 3, Newgate Centre';
	$sites{'1229'}->{'postalCode'}   = 'CAUTENG 2113';
	$sites{'1229'}->{'city'}         = 'Johannesburg';
	$sites{'1229'}->{'investigator'} = 'Essack Mitha';
	$sites{'1229'}->{'latitude'}     = '-26.203004';
	$sites{'1229'}->{'longitude'}    = '28.036724';
	# 1230
	$sites{'1230'}->{'name'}         = 'Limpopo Clinical Research Initiative, Tamboti Medical Centre';
	$sites{'1230'}->{'address'}      = '11 Van der Hip Street';
	$sites{'1230'}->{'postalCode'}   = 'LIMPOPO 0380';
	$sites{'1230'}->{'city'}         = 'Thabazimbi';
	$sites{'1230'}->{'investigator'} = 'Leon Fouche';
	$sites{'1230'}->{'latitude'}     = '-24.591370';
	$sites{'1230'}->{'longitude'}    = '27.406048';
	# 1231
	$sites{'1231'}->{'name'}         = 'Hospital Militar Central Cirujano Mayor Dr';
	$sites{'1231'}->{'address'}      = 'Louis Maria Campos 726 Piso 8';
	$sites{'1231'}->{'postalCode'}   = '1426';
	$sites{'1231'}->{'city'}         = 'Caba';
	$sites{'1231'}->{'investigator'} = 'Fernando Polack';
	$sites{'1231'}->{'latitude'}     = '-34.569624';
	$sites{'1231'}->{'longitude'}    = '-58.437341';
	# 1232
	$sites{'1232'}->{'name'}         = 'IACT Health';
	$sites{'1232'}->{'address'}      = '800 Talbotton Rd';
	$sites{'1232'}->{'postalCode'}   = 'GA 31904';
	$sites{'1232'}->{'city'}         = 'Columbus';
	$sites{'1232'}->{'investigator'} = 'Jeffrey Kingsley';
	$sites{'1232'}->{'latitude'}     = '32.483183';
	$sites{'1232'}->{'longitude'}    = '-84.982224';
	# 1235
	$sites{'1235'}->{'name'}         = 'LSUHSC-Shreveport';
	$sites{'1235'}->{'address'}      = '1801 Fairfield Ave, Ste 203';
	$sites{'1235'}->{'postalCode'}   = 'LA 71101';
	$sites{'1235'}->{'city'}         = 'Shreveport';
	$sites{'1235'}->{'investigator'} = 'John Vanchiere';
	$sites{'1235'}->{'latitude'}     = '32.494217';
	$sites{'1235'}->{'longitude'}    = '-93.751993';
	# 1241
	$sites{'1241'}->{'name'}         = 'Hospital Santo Antonio Associacao Obras Sociais';
	$sites{'1241'}->{'address'}      = 'Avenida Dendeziros do Bonfim, n°161';
	$sites{'1241'}->{'postalCode'}   = 'BAHIA CEP 40415-006';
	$sites{'1241'}->{'city'}         = 'Salvador';
	$sites{'1241'}->{'investigator'} = 'Edson Moreira';
	$sites{'1241'}->{'latitude'}     = '-12.934974';
	$sites{'1241'}->{'longitude'}    = '-38.506831';
	# 1246
	$sites{'1246'}->{'name'}         = 'Jongaie Research';
	$sites{'1246'}->{'address'}      = 'Medicross Pretoria West, 1st Floor, 551 WF Nkomo Street';
	$sites{'1246'}->{'postalCode'}   = 'GAUTENG 0183';
	$sites{'1246'}->{'city'}         = 'Pretoria';
	$sites{'1246'}->{'investigator'} = 'Dany Musungaie';
	$sites{'1246'}->{'latitude'}     = '-25.748881';
	$sites{'1246'}->{'longitude'}    = '28.149101';
	# 1247
	$sites{'1247'}->{'name'}         = 'Tiervlei Trial Centre, Basement Level, Karl Bremer Hospital';
	$sites{'1247'}->{'address'}      = 'c/o Mike Bienaar Boulevard & Frans Coradie Avenue, Bellville';
	$sites{'1247'}->{'postalCode'}   = 'WESTERN CAPE 7530';
	$sites{'1247'}->{'city'}         = 'Cape Town';
	$sites{'1247'}->{'investigator'} = 'Haylene Nell';
	$sites{'1247'}->{'latitude'}     = '-33.871827';
	$sites{'1247'}->{'longitude'}    = '18.637222';
	# 1248
	$sites{'1248'}->{'name'}         = 'Pharmaron CPC, Inc.';
	$sites{'1248'}->{'address'}      = '800 W Baltimore St, 5th and 6th Fl';
	$sites{'1248'}->{'postalCode'}   = 'MARYLAND 21201';
	$sites{'1248'}->{'city'}         = 'Baltimore';
	$sites{'1248'}->{'investigator'} = 'Mohamed Al-Ibrahim';
	$sites{'1248'}->{'latitude'}     = '39.289088';
	$sites{'1248'}->{'longitude'}    = '-76.628981';
	# 1251
	$sites{'1251'}->{'name'}         = 'Birmingham Clinical Research Unit';
	$sites{'1251'}->{'address'}      = '2017 Cayon Rd, Ste 41';
	$sites{'1251'}->{'postalCode'}   = 'ALABAMA 35216';
	$sites{'1251'}->{'city'}         = 'Birmingham';
	$sites{'1251'}->{'investigator'} = 'Hayes Williams';
	$sites{'1251'}->{'latitude'}     = '33.444924';
	$sites{'1251'}->{'longitude'}    = '-86.789571';
	# 1252
	$sites{'1252'}->{'name'}         = 'Main Street Physician\'s Care';
	$sites{'1252'}->{'address'}      = '3612 Mitchell St';
	$sites{'1252'}->{'postalCode'}   = 'SOUTH CAROLINA 29569';
	$sites{'1252'}->{'city'}         = 'Loris';
	$sites{'1252'}->{'investigator'} = 'Stephen Grubb';
	$sites{'1252'}->{'latitude'}     = '34.056590';
	$sites{'1252'}->{'longitude'}    = '-78.898022';
	# 1254
	$sites{'1254'}->{'name'}         = 'Bayview Research Group';
	$sites{'1254'}->{'address'}      = '12626 Riverside Dr, Ste 404';
	$sites{'1254'}->{'postalCode'}   = 'CALIFORNIA 91607';
	$sites{'1254'}->{'city'}         = 'Valley Village';
	$sites{'1254'}->{'investigator'} = 'Robert Heller';
	$sites{'1254'}->{'latitude'}     = '34.156794';
	$sites{'1254'}->{'longitude'}    = '-118.408083';
	# 1258
	$sites{'1258'}->{'name'}         = 'Dayton Clinical Research';
	$sites{'1258'}->{'address'}      = '1100 Salem Ave';
	$sites{'1258'}->{'postalCode'}   = 'OH 45406';
	$sites{'1258'}->{'city'}         = 'Dayton';
	$sites{'1258'}->{'investigator'} = 'Martin Schear';
	$sites{'1258'}->{'latitude'}     = '39.774991';
	$sites{'1258'}->{'longitude'}    = '-84.216896';
	# 1260
	$sites{'1260'}->{'name'}         = 'UMass Memorial Medical Center - University';
	$sites{'1260'}->{'address'}      = '55 Lake Ave N';
	$sites{'1260'}->{'postalCode'}   = 'MASSACHUSETTS 01655';
	$sites{'1260'}->{'city'}         = 'Worcester';
	$sites{'1260'}->{'investigator'} = 'Robert Finberg';
	$sites{'1260'}->{'latitude'}     = '42.275392';
	$sites{'1260'}->{'longitude'}    = '-71.762984';
	# 1261
	$sites{'1261'}->{'name'}         = 'Benaroya Research Institute at Virginia Mason';
	$sites{'1261'}->{'address'}      = '55 Lake Ave N';
	$sites{'1261'}->{'postalCode'}   = 'MASSACHUSETTS 01655';
	$sites{'1261'}->{'city'}         = 'Worcester';
	$sites{'1261'}->{'investigator'} = 'Carla Greenbaum';
	$sites{'1261'}->{'latitude'}     = '42.275392';
	$sites{'1261'}->{'longitude'}    = '-71.762984';
	# 1264
	$sites{'1264'}->{'name'}         = 'UC Davis Medical Center';
	$sites{'1264'}->{'address'}      = '2315 Stockton Blvd';
	$sites{'1264'}->{'postalCode'}   = 'CA 95817';
	$sites{'1264'}->{'city'}         = 'Sacramento';
	$sites{'1264'}->{'investigator'} = 'Timothy Albertson';
	$sites{'1264'}->{'latitude'}     = '38.554260';
	$sites{'1264'}->{'longitude'}    = '-121.455454';
	# 1265
	$sites{'1265'}->{'name'}         = 'Kaiser Petmanente Los Angeles Medical Center';
	$sites{'1265'}->{'address'}      = 'Edgemont Medical Offices 1526 N Edgemont St';
	$sites{'1265'}->{'postalCode'}   = 'CA 90027';
	$sites{'1265'}->{'city'}         = 'Los Angeles';
	$sites{'1265'}->{'investigator'} = 'William Towner';
	$sites{'1265'}->{'latitude'}     = '34.098208';
	$sites{'1265'}->{'longitude'}    = '-118.295618';
	# 1269
	$sites{'1269'}->{'name'}         = 'Providence Clinical Research';
	$sites{'1269'}->{'address'}      = '6400 Laurel Canyon Blvd, Ste 300A';
	$sites{'1269'}->{'postalCode'}   = 'CA 91606';
	$sites{'1269'}->{'city'}         = 'North Hollywood';
	$sites{'1269'}->{'investigator'} = 'Teresa Sligh';
	$sites{'1269'}->{'latitude'}     = '34.187014';
	$sites{'1269'}->{'longitude'}    = '-118.396461';
	# 1270
	$sites{'1270'}->{'name'}         = 'Kaiser Petmanente Sacramento ';
	$sites{'1270'}->{'address'}      = '1650 Response Rd';
	$sites{'1270'}->{'postalCode'}   = 'CA 95815';
	$sites{'1270'}->{'city'}         = 'Sacramento';
	$sites{'1270'}->{'investigator'} = 'Nicola Klein';
	$sites{'1270'}->{'latitude'}     = '38.595300';
	$sites{'1270'}->{'longitude'}    = '-121.429827';
	# 4444
	$sites{'4444'}->{'name'}         = 'Not Listed';
	$sites{'4444'}->{'address'}      = 'Not Listed';
	$sites{'4444'}->{'postalCode'}   = 'Not Listed';
	$sites{'4444'}->{'city'}         = 'Not Listed';
	$sites{'4444'}->{'investigator'} = 'Not Listed';
	$sites{'4444'}->{'latitude'}     = '';
	$sites{'4444'}->{'longitude'}    = '';

	# Displaying total sites.
	my $totalSites   = keys %sites;
	say "$totalSites sites listed.";
}

sub load_patients {
	my $json;
	my $file = 'raw_data/pfizer_trials/merged_randomization_and_demographic.json';
	open my $in, '<:utf8', $file;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%patients = %$json;
}