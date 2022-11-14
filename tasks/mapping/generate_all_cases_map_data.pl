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

# Sites localisation comes from https://openvaet.org/pfizearch/viewer?pdf=pfizer_documents/native_files/pd-production-111721/5.2-listing-of-clinical-sites-and-cvs-pages-1-41.pdf&currentLanguage=en
# Raw patient testing data comes this article https://openvaet.org/pfizearch/viewer?pdf=pfizer_documents/native_files/pd-production-070122/125742_S1_M5_5351_c4591001-interim-mth6-lab-measurements-sensitive.pdf&currentLanguage=en


# Loading sites data.
my %sites = ();
config_sites();

# We load the file produced by the daily clout.
my $sitesFile   = 'raw_data/pfizer_trials/170-Efficacy-Population-Analysis-19-23-days-protocol-deviaition-chart-26-Sep-2022-Final.csv';
my %stats       = ();
my $patientsNum = 0;
open my $in, '<:utf8', $sitesFile;
while (<$in>) {
	chomp $_;
	my (undef, $siteNum, $countryData) = split ';', $_;
	next unless $siteNum && $countryData;
	my ($siteCode)   = $siteNum =~ /........ (....) ......../;
	my $siteName     = $sites{$siteCode}->{'name'}         // die;
	my $latitude     = $sites{$siteCode}->{'latitude'}     // die;
	my $longitude    = $sites{$siteCode}->{'longitude'}    // die;
	my $investigator = $sites{$siteCode}->{'investigator'} // die;
	my $address      = $sites{$siteCode}->{'address'};
	my $postalCode   = $sites{$siteCode}->{'postalCode'};
	my $city         = $sites{$siteCode}->{'city'};
	my ($countryCode3, $age, $sex) = $countryData =~ /\((...)\/(..)\/(.)\)/;
	# say "$siteNum -> $siteCode, $countryData -> $countryCode3, $age, $sex";
	$patientsNum++;
	$stats{'By Countries'}->{$countryCode3}++;
	# $stats{'By Ages'}->{$age}++;
	# $stats{'By Sexes'}->{$sex}++;
	$stats{'By Sites Codes'}->{$siteCode}->{'totalCases'}++;
	$stats{'By Sites Codes'}->{$siteCode}->{'address'}  = $address;
	$stats{'By Sites Codes'}->{$siteCode}->{'postalCode'}  = $postalCode;
	$stats{'By Sites Codes'}->{$siteCode}->{'city'}  = $city;
	$stats{'By Sites Codes'}->{$siteCode}->{'latitude'}  = $latitude;
	$stats{'By Sites Codes'}->{$siteCode}->{'longitude'} = $longitude;
	$stats{'By Sites Codes'}->{$siteCode}->{'investigator'} = $investigator;
	$stats{'By Sites Codes'}->{$siteCode}->{'siteName'}  = $siteName;
}
close $in;

# Printing the usable files.
open my $out, '>:utf8', 'public/doc/pfizer_trial_cases_mapping/data_by_sites.csv';
say $out "site code;site name;total cases;latitude;longitude;address;postal code;city;";
my @sitesData = ();
for my $siteCode (sort keys %{$stats{'By Sites Codes'}}) {
	my $latitude   = $stats{'By Sites Codes'}->{$siteCode}->{'latitude'};
	my $longitude  = $stats{'By Sites Codes'}->{$siteCode}->{'longitude'};
	my $siteName  = $stats{'By Sites Codes'}->{$siteCode}->{'siteName'}  // die;
	my $address  = $stats{'By Sites Codes'}->{$siteCode}->{'address'}  // die;
	my $postalCode  = $stats{'By Sites Codes'}->{$siteCode}->{'postalCode'}  // die;
	my $investigator  = $stats{'By Sites Codes'}->{$siteCode}->{'investigator'}  // die;
	my $city  = $stats{'By Sites Codes'}->{$siteCode}->{'city'}  // die;
	my $totalCases = $stats{'By Sites Codes'}->{$siteCode}->{'totalCases'} // die;
	say $out "$siteCode;$siteName;$totalCases;$latitude;$longitude;$address;$postalCode;$city;";
	my %o = %{$stats{'By Sites Codes'}->{$siteCode}};
	$o{'siteCode'} = $siteCode;
	push @sitesData, \%o;
}
close $out;
open my $jOut, '>:utf8', 'public/doc/pfizer_trial_cases_mapping/data_by_sites.json';
print $jOut encode_json\@sitesData;
close $jOut;
open my $jOut2, '>:utf8', 'public/doc/pfizer_trial_cases_mapping/stats_by_sites.json';
print $jOut2 encode_json\%stats;
close $jOut2;

sub config_sites {
	# 1003
	$sites{'1003'}->{'name'}         = 'Rochester Regional Health/Rochester General Hospital, Infectious Desease Department';
	$sites{'1003'}->{'address'}      = '1425 Portland Avenue';
	$sites{'1003'}->{'postalCode'}   = 'NY 14621';
	$sites{'1003'}->{'city'}         = 'Rochester';
	$sites{'1003'}->{'investigator'} = 'Edward Walsh';
	$sites{'1003'}->{'latitude'}     = '43.192742';
	$sites{'1003'}->{'longitude'}    = '-77.585667';
	# 1006
	$sites{'1006'}->{'name'}         = 'J. Lewis Research Inc. / Foothill Family Clinic';
	$sites{'1006'}->{'address'}      = '2295 Foothill Dr';
	$sites{'1006'}->{'postalCode'}   = 'UT 84109';
	$sites{'1006'}->{'city'}         = 'Salt Lake City';
	$sites{'1006'}->{'investigator'} = 'James Peterson';
	$sites{'1006'}->{'latitude'}     = '40.721491';
	$sites{'1006'}->{'longitude'}    = '-111.811763';
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
	# 1013
	$sites{'1013'}->{'name'}         = 'Clinical Neuroscience Solutions, Inc';
	$sites{'1013'}->{'address'}      = '618 E. S St, Ste 100';
	$sites{'1013'}->{'postalCode'}   = 'FL 32801';
	$sites{'1013'}->{'city'}         = 'Orlando';
	$sites{'1013'}->{'investigator'} = 'Michael Dever';
	$sites{'1013'}->{'latitude'}     = '28.537427';
	$sites{'1013'}->{'longitude'}    = '-81.368636';
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
	# 1028
	$sites{'1028'}->{'name'}         = 'Lillestol Research LLC';
	$sites{'1028'}->{'address'}      = '4450 31st Ave S, Ste 101';
	$sites{'1028'}->{'postalCode'}   = 'ND 58104';
	$sites{'1028'}->{'city'}         = 'Fargo';
	$sites{'1028'}->{'investigator'} = 'Michael Lillestol';
	$sites{'1028'}->{'latitude'}     = '46.833424';
	$sites{'1028'}->{'longitude'}    = '-96.860613';
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
	# 1046
	$sites{'1046'}->{'name'}         = 'North Alabama Research Center, LLC';
	$sites{'1046'}->{'address'}      = '721 W Market St, Ste B';
	$sites{'1046'}->{'postalCode'}   = 'AL 35801';
	$sites{'1046'}->{'city'}         = 'Athens';
	$sites{'1046'}->{'investigator'} = 'Ernest Hendrix';
	$sites{'1046'}->{'latitude'}     = '34.803263';
	$sites{'1046'}->{'longitude'}    = '-86.980871';
	# 1047
	$sites{'1047'}->{'name'}         = 'Medical Affliated Research Center';
	$sites{'1047'}->{'address'}      = '303 Williams Ave, Ste 511';
	$sites{'1047'}->{'postalCode'}   = 'AL 35801';
	$sites{'1047'}->{'city'}         = 'Huntsville';
	$sites{'1047'}->{'investigator'} = 'James McMurray';
	$sites{'1047'}->{'latitude'}     = '34.725469';
	$sites{'1047'}->{'longitude'}    = '-86.585356';
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
	# 1077
	$sites{'1077'}->{'name'}         = 'Meridian Clinical Research LLC';
	$sites{'1077'}->{'address'}      = '409 Hooper Rd';
	$sites{'1077'}->{'postalCode'}   = 'NEW YORK 13760';
	$sites{'1077'}->{'city'}         = 'Endwell';
	$sites{'1077'}->{'investigator'} = 'Suchet Patel';
	$sites{'1077'}->{'latitude'}     = '42.114451';
	$sites{'1077'}->{'longitude'}    = '-76.017445';
	# 1079
	$sites{'1079'}->{'name'}         = 'PMG Research of Raleigh, LLC, d/b/a PMG';
	$sites{'1079'}->{'address'}      = '530 New Waverly Place, Ste 200A';
	$sites{'1079'}->{'postalCode'}   = 'NC 27518';
	$sites{'1079'}->{'city'}         = 'Cary';
	$sites{'1079'}->{'investigator'} = 'George Raad';
	$sites{'1079'}->{'latitude'}     = '35.737095';
	$sites{'1079'}->{'longitude'}    = '-78.776400';
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
	# 1085
	$sites{'1085'}->{'name'}         = 'Ventavia Research Group, LLC';
	$sites{'1085'}->{'address'}      = '300 N Rufe Snow Dr';
	$sites{'1085'}->{'postalCode'}   = 'TX 76248';
	$sites{'1085'}->{'city'}         = 'Keller';
	$sites{'1085'}->{'investigator'} = 'Gregory Fuller';
	$sites{'1085'}->{'latitude'}     = '32.937803';
	$sites{'1085'}->{'longitude'}    = '-97.229835';
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
	$sites{'1126'}->{'latitude'}     = '38.595276';
	$sites{'1126'}->{'longitude'}    = '-121.429798';
	# 1128
	$sites{'1128'}->{'name'}         = 'Ventavia Research Group, LLC';
	$sites{'1128'}->{'address'}      = '1307 8th Ave, Ste 202 & Ste M1';
	$sites{'1128'}->{'postalCode'}   = 'TX 76104';
	$sites{'1128'}->{'city'}         = 'Fort Worth';
	$sites{'1128'}->{'investigator'} = 'Mark Koch';
	$sites{'1128'}->{'latitude'}     = '32.730420';
	$sites{'1128'}->{'longitude'}    = '-97.342842';
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
	# 1141
	$sites{'1141'}->{'name'}         = 'University of Iowa Hospitals & Clinics';
	$sites{'1141'}->{'address'}      = '200 Hawkins Dr';
	$sites{'1141'}->{'postalCode'}   = 'IA 52242';
	$sites{'1141'}->{'city'}         = 'Iowa City';
	$sites{'1141'}->{'investigator'} = 'Patricia Winokur';
	$sites{'1141'}->{'latitude'}     = '41.660436';
	$sites{'1141'}->{'longitude'}    = '-91.548543';
	# 1149
	$sites{'1149'}->{'name'}         = 'Collaborative Neuroscience Research, LLC';
	$sites{'1149'}->{'address'}      = '12772 Valley View St, Ste 3';
	$sites{'1149'}->{'postalCode'}   = 'CA 92845';
	$sites{'1149'}->{'city'}         = 'Garden Grove';
	$sites{'1149'}->{'investigator'} = 'Steven Reynolds';
	$sites{'1149'}->{'latitude'}     = '33.777543';
	$sites{'1149'}->{'longitude'}    = '-118.034075';
	# 1152
	$sites{'1152'}->{'name'}         = 'California Research Foundation';
	$sites{'1152'}->{'address'}      = '4180 Ruffin Rd, Ste 255';
	$sites{'1152'}->{'postalCode'}   = 'CALIFORNIA 92123-1881';
	$sites{'1152'}->{'city'}         = 'San Diego';
	$sites{'1152'}->{'investigator'} = 'Donald Branson';
	$sites{'1152'}->{'latitude'}     = '32.817426';
	$sites{'1152'}->{'longitude'}    = '-117.124983';
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
	# 1170
	$sites{'1170'}->{'name'}         = 'North Texas Infectious Deseases Consultants, P.A.';
	$sites{'1170'}->{'address'}      = '3409 Worth St, Ste 710, 725, 740';
	$sites{'1170'}->{'postalCode'}   = 'TEXAS 75246';
	$sites{'1170'}->{'city'}         = 'Dallas';
	$sites{'1170'}->{'investigator'} = 'Mezgebe Berhe';
	$sites{'1170'}->{'latitude'}     = '32.788375';
	$sites{'1170'}->{'longitude'}    = '-96.779399';
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
	# 1223
	$sites{'1223'}->{'name'}         = 'Yale Center for Clinical Investigations';
	$sites{'1223'}->{'address'}      = '2 Church St S, Ste 114';
	$sites{'1223'}->{'postalCode'}   = 'CT 06510';
	$sites{'1223'}->{'city'}         = 'New Haven';
	$sites{'1223'}->{'investigator'} = 'Onyema Ogbuagu';
	$sites{'1223'}->{'latitude'}     = '41.301948';
	$sites{'1223'}->{'longitude'}    = '-72.930261';
	# 1226
	$sites{'1226'}->{'name'}         = 'CEPIC - Centro Paulista de Investigacao Clinica e Servicos Medicos Ltda (Casa Blanca)';
	$sites{'1226'}->{'address'}      = 'Rua Moreira e Costa, 342 - Ipiranga';
	$sites{'1226'}->{'postalCode'}   = 'SP 04266-010';
	$sites{'1226'}->{'city'}         = 'Sao Paulo';
	$sites{'1226'}->{'investigator'} = 'Cristiano Zerbini';
	$sites{'1226'}->{'latitude'}     = '-23.589737';
	$sites{'1226'}->{'longitude'}    = '-46.611078';
	# 1231
	$sites{'1231'}->{'name'}         = 'Hospital Militar Central Cirujano Mayor Dr';
	$sites{'1231'}->{'address'}      = 'Louis Maria Campos 726 Piso 8';
	$sites{'1231'}->{'postalCode'}   = '1426';
	$sites{'1231'}->{'city'}         = 'Caba';
	$sites{'1231'}->{'investigator'} = 'Fernando Polack';
	$sites{'1231'}->{'latitude'}     = '-34.569624';
	$sites{'1231'}->{'longitude'}    = '-58.437341';
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
	# 1251
	$sites{'1251'}->{'name'}         = 'Birmingham Clinical Research Unit';
	$sites{'1251'}->{'address'}      = '2017 Cayon Rd, Ste 41';
	$sites{'1251'}->{'postalCode'}   = 'ALABAMA 35216';
	$sites{'1251'}->{'city'}         = 'Birmingham';
	$sites{'1251'}->{'investigator'} = 'Hayes Williams';
	$sites{'1251'}->{'latitude'}     = '33.444924';
	$sites{'1251'}->{'longitude'}    = '-86.789571';
	# 4444
	$sites{'4444'}->{'name'}         = 'Not Listed';
	$sites{'4444'}->{'address'}      = 'Not Listed';
	$sites{'4444'}->{'postalCode'}   = 'Not Listed';
	$sites{'4444'}->{'city'}         = 'Not Listed';
	$sites{'4444'}->{'investigator'} = 'Not Listed';
	$sites{'4444'}->{'latitude'}     = '';
	$sites{'4444'}->{'longitude'}    = '';
}