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
use Encode;
use Encode::Unicode;
use JSON;
use FindBin;
use Scalar::Util qw(looks_like_number);
use File::stat;
use lib "$FindBin::Bin/../../../lib";

# Project's libraries.
use config;
use global;
use time;

system("perl tasks/studies/cdc_mortality/get_2021_data.pl");

my $statsInFile  = 'tasks/studies/cdc_mortality/current_2021_data.json';
my $statsOutFile = 'stats/cdc_mortality.json';

my %yearlyValues = ();
parse_raw_file();

my %obj = (); # Will store the JSON values we will export.
format_stats_objects();

load_2021_values();

sub parse_raw_file {
	my %dates = ();
	my $cdcFile;
	my $cdcFolder = "tasks/studies/cdc_mortality/";
	my $fileExt;
	for my $file (glob "$cdcFolder*.csv") {
		say $file;
		(undef, $file) = split 'cdc_mortality\/', $file;
		(my $date, $fileExt) = split '_', $file;
		$dates{$date} = 1;
	}
	for my $date (sort{$b <=> $a} keys %dates) {
		$cdcFile = $cdcFolder . $date . '_' . $fileExt;
		last;
	}
	die "Failed to find the expected CDC file in [$cdcFolder]." unless -f $cdcFile;
	open my $in, '<:utf8', $cdcFile;
	my $lNum = 0;
	my @labels;
	while (<$in>) {
		$lNum++;
		if ($lNum == 1) {
			@labels = split ';', $_;
		} else {
			die unless scalar @labels;
			my @values = split ';', $_;
			die unless scalar @values == scalar @labels;
			my $year       = $values[0] // die;
			my $yearStatus = $values[1] // die;
			die unless $year && looks_like_number $year && $year =~ /^....$/;
			die unless $yearStatus && ($yearStatus eq 'final' || $yearStatus eq 'provisional');
			my $vNum = 0;
			for my $value (@values) {
				my $label = $labels[$vNum] // die;
				$label =~ s/\n//;
				$value =~ s/\n//;
				$vNum++;
				$yearlyValues{$yearStatus}->{$year}->{$label} = $value;
			}
		}
	}
	close $in;
	unless (
		exists $yearlyValues{'final'}->{'2014'} &&
		exists $yearlyValues{'final'}->{'2015'} &&
		exists $yearlyValues{'final'}->{'2016'} &&
		exists $yearlyValues{'final'}->{'2017'} &&
		exists $yearlyValues{'final'}->{'2018'} &&
		exists $yearlyValues{'final'}->{'2019'} &&
		exists $yearlyValues{'provisional'}->{'2020'} &&
		exists $yearlyValues{'provisional'}->{'2021'}
	) {
		die "Not the expected years format in .CSV file ; code should be verified.";
	}
}

sub format_stats_objects {
	# Formatting values from the years finalized.
	for my $year (sort{$a <=> $b} keys %{$yearlyValues{'final'}}) {
		my %rawObj = %{$yearlyValues{'final'}->{$year}};
		# p%rawObj;
		# die;

		# Fetching raw data from source file.
		# global stats.
		my $globalDeaths                             = $rawObj{'globalDeaths'}                             // die;
		my $globAlzheimer                            = $rawObj{'globAlzheimer'}                            // die;
		my $globAlzheimerCases                       = $rawObj{'globAlzheimerCases'}                       // die;
		my $globDeathsCancer                         = $rawObj{'globDeathsCancer'}                         // die;
		my $globDeathsCancerCases                    = $rawObj{'globDeathsCancerCases'}                    // die;
		my $globDeathsChronicRespiratoryDisease      = $rawObj{'globDeathsChronicRespiratoryDisease'}      // die;
		my $globDeathsChronicRespiratoryDiseaseCases = $rawObj{'globDeathsChronicRespiratoryDiseaseCases'} // die;
		my $globDeathsHeartDisease                   = $rawObj{'globDeathsHeartDisease'}                   // die;
		my $globDeathsHeartDiseaseCases              = $rawObj{'globDeathsHeartDiseaseCases'}              // die;
		my $globDiabetes                             = $rawObj{'globDiabetes'}                             // die;
		my $globDiabetesCases                        = $rawObj{'globDiabetesCases'}                        // die;
		my $globInfluenzaAndPneumonia                = $rawObj{'globInfluenzaAndPneumonia'}                // die;
		my $globInfluenzaAndPneumoniaCases           = $rawObj{'globInfluenzaAndPneumoniaCases'}           // die;
		my $globKidneyDisease                        = $rawObj{'globKidneyDisease'}                        // die;
		my $globKidneyDiseaseCases                   = $rawObj{'globKidneyDiseaseCases'}                   // die;
		my $globStrokes                              = $rawObj{'globStrokes'}                              // die;
		my $globStrokesCases                         = $rawObj{'globStrokesCases'}                         // die;
		my $globSuicide                              = $rawObj{'globSuicide'}                              // die;
		my $globSuicideCases                         = $rawObj{'globSuicideCases'}                         // die;
		my $globUnintentionalInjuries                = $rawObj{'globUnintentionalInjuries'}                // die;
		my $globUnintentionalInjuriesCases           = $rawObj{'globUnintentionalInjuriesCases'}           // die;

		# age-adjusted death rates for race-ethnicity-sex groups raw values.
		my $ageAdjDRRESGBlackFemale                  = $rawObj{'ageAdjDRRESGBlackFemale'}                  // die;
		my $ageAdjDRRESGBlackMale                    = $rawObj{'ageAdjDRRESGBlackMale'}                    // die;
		my $ageAdjDRRESGHispanicFemale               = $rawObj{'ageAdjDRRESGHispanicFemale'}               // die;
		my $ageAdjDRRESGHispanicMale                 = $rawObj{'ageAdjDRRESGHispanicMale'}                 // die;
		my $ageAdjDRRESGTotal                        = $rawObj{'ageAdjDRRESGTotal'}                        // die;
		my $ageAdjDRRESGWhiteFemale                  = $rawObj{'ageAdjDRRESGWhiteFemale'}                  // die;
		my $ageAdjDRRESGWhiteMale                    = $rawObj{'ageAdjDRRESGWhiteMale'}                    // die;

		# infants stats
		my $infantDeathsBacterialSepsis              = $rawObj{'infantDeathsBacterialSepsis'}              // die;
		my $infantDeathsCongenitalMalformations      = $rawObj{'infantDeathsCongenitalMalformations'}      // die;
		my $infantDeathsCordComplication             = $rawObj{'infantDeathsCordComplication'}             // die;
		my $infantDeathsLowBirthWeight               = $rawObj{'infantDeathsLowBirthWeight'}               // die;
		my $infantDeathsMaternalComplication         = $rawObj{'infantDeathsMaternalComplication'}         // die;
		my $infantDeathsPer100000Births              = $rawObj{'infantDeathsPer100000Births'}              // die;
		my $infantDeathsSuddenDeathSyndrom           = $rawObj{'infantDeathsSuddenDeathSyndrom'}           // die;
		my $infantDeathsUnintentionalInjuries        = $rawObj{'infantDeathsUnintentionalInjuries'}        // die;
		my $infantDiseasesOfCirculatorySystem        = $rawObj{'infantDiseasesOfCirculatorySystem'}        // die;
		my $infantNeonatalHemorrhage                 = $rawObj{'infantNeonatalHemorrhage'}                 // die;
		my $infantRespiratoryDistress                = $rawObj{'infantRespiratoryDistress'}                // die;

		# say "*" x 60;
		# say "*" x 60;
		# say "year                                     : $year";
		# say "*" x 60;
		# say "*" x 60;

		# say "globalDeaths                             : $globalDeaths";
		# say "globAlzheimer                            : $globAlzheimer";
		# say "globAlzheimerCases                       : $globAlzheimerCases";
		# say "globDeathsHeartDisease                   : $globDeathsHeartDisease";
		# say "globDeathsHeartDiseaseCases              : $globDeathsHeartDiseaseCases";
		# say "globDeathsCancer                         : $globDeathsCancer";
		# say "globDeathsCancerCases                    : $globDeathsCancerCases";
		# say "globDeathsChronicRespiratoryDisease      : $globDeathsChronicRespiratoryDisease";
		# say "globDeathsChronicRespiratoryDiseaseCases : $globDeathsChronicRespiratoryDiseaseCases";
		# say "globDiabetes                             : $globDiabetes";
		# say "globDiabetesCases                        : $globDiabetesCases";
		# say "globInfluenzaAndPneumonia                : $globInfluenzaAndPneumonia";
		# say "globInfluenzaAndPneumoniaCases           : $globInfluenzaAndPneumoniaCases";
		# say "globKidneyDisease                        : $globKidneyDisease";
		# say "globKidneyDiseaseCases                   : $globKidneyDiseaseCases";
		# say "globStrokes                              : $globStrokes";
		# say "globStrokesCases                         : $globStrokesCases";
		# say "globSuicide                              : $globSuicide";
		# say "globSuicideCases                         : $globSuicideCases";
		# say "globUnintentionalInjuries                : $globUnintentionalInjuries";
		# say "globUnintentionalInjuriesCases           : $globUnintentionalInjuriesCases";

		# say "ageAdjDRRESGTotal                        : $ageAdjDRRESGTotal";
		# say "ageAdjDRRESGWhiteMale                    : $ageAdjDRRESGWhiteMale";
		# say "ageAdjDRRESGWhiteFemale                  : $ageAdjDRRESGWhiteFemale";
		# say "ageAdjDRRESGHispanicMale                 : $ageAdjDRRESGHispanicMale";
		# say "ageAdjDRRESGHispanicFemale               : $ageAdjDRRESGHispanicFemale";
		# say "ageAdjDRRESGBlackMale                    : $ageAdjDRRESGBlackMale";
		# say "ageAdjDRRESGBlackFemale                  : $ageAdjDRRESGBlackFemale";

		# say "infantDeathsBacterialSepsis              : $infantDeathsBacterialSepsis";
		# say "infantDeathsCongenitalMalformations      : $infantDeathsCongenitalMalformations";
		# say "infantDeathsCordComplication             : $infantDeathsCordComplication";
		# say "infantDeathsLowBirthWeight               : $infantDeathsLowBirthWeight";
		# say "infantDeathsMaternalComplication         : $infantDeathsMaternalComplication";
		# say "infantDeathsPer100000Births              : $infantDeathsPer100000Births";
		# say "infantDeathsSuddenDeathSyndrom           : $infantDeathsSuddenDeathSyndrom";
		# say "infantDeathsUnintentionalInjuries        : $infantDeathsUnintentionalInjuries";
		# say "infantDiseasesOfCirculatorySystem        : $infantDiseasesOfCirculatorySystem";
		# say "infantNeonatalHemorrhage                 : $infantNeonatalHemorrhage";
		# say "infantRespiratoryDistress                : $infantRespiratoryDistress";
		$obj{'final'}->{$year}->{'global'}->{'globalDeaths'} = $globalDeaths;
		$obj{'final'}->{$year}->{'global'}->{'globAlzheimer'} = $globAlzheimer;
		$obj{'final'}->{$year}->{'global'}->{'globAlzheimerCases'} = $globAlzheimerCases;
		$obj{'final'}->{$year}->{'global'}->{'globDeathsHeartDisease'} = $globDeathsHeartDisease;
		$obj{'final'}->{$year}->{'global'}->{'globDeathsHeartDiseaseCases'} = $globDeathsHeartDiseaseCases;
		$obj{'final'}->{$year}->{'global'}->{'globDeathsCancer'} = $globDeathsCancer;
		$obj{'final'}->{$year}->{'global'}->{'globDeathsCancerCases'} = $globDeathsCancerCases;
		$obj{'final'}->{$year}->{'global'}->{'globDeathsChronicRespiratoryDisease'} = $globDeathsChronicRespiratoryDisease;
		$obj{'final'}->{$year}->{'global'}->{'globDeathsChronicRespiratoryDiseaseCases'} = $globDeathsChronicRespiratoryDiseaseCases;
		$obj{'final'}->{$year}->{'global'}->{'globDiabetes'} = $globDiabetes;
		$obj{'final'}->{$year}->{'global'}->{'globDiabetesCases'} = $globDiabetesCases;
		$obj{'final'}->{$year}->{'global'}->{'globInfluenzaAndPneumonia'} = $globInfluenzaAndPneumonia;
		$obj{'final'}->{$year}->{'global'}->{'globInfluenzaAndPneumoniaCases'} = $globInfluenzaAndPneumoniaCases;
		$obj{'final'}->{$year}->{'global'}->{'globKidneyDisease'} = $globKidneyDisease;
		$obj{'final'}->{$year}->{'global'}->{'globKidneyDiseaseCases'} = $globKidneyDiseaseCases;
		$obj{'final'}->{$year}->{'global'}->{'globStrokes'} = $globStrokes;
		$obj{'final'}->{$year}->{'global'}->{'globStrokesCases'} = $globStrokesCases;
		$obj{'final'}->{$year}->{'global'}->{'globSuicide'} = $globSuicide;
		$obj{'final'}->{$year}->{'global'}->{'globSuicideCases'} = $globSuicideCases;
		$obj{'final'}->{$year}->{'global'}->{'globUnintentionalInjuries'} = $globUnintentionalInjuries;
		$obj{'final'}->{$year}->{'global'}->{'globUnintentionalInjuriesCases'} = $globUnintentionalInjuriesCases;

		$obj{'final'}->{$year}->{'aADR'}->{'ageAdjDRRESGTotal'} = $ageAdjDRRESGTotal;
		$obj{'final'}->{$year}->{'aADR'}->{'ageAdjDRRESGWhiteMale'} = $ageAdjDRRESGWhiteMale;
		$obj{'final'}->{$year}->{'aADR'}->{'ageAdjDRRESGWhiteFemale'} = $ageAdjDRRESGWhiteFemale;
		$obj{'final'}->{$year}->{'aADR'}->{'ageAdjDRRESGHispanicMale'} = $ageAdjDRRESGHispanicMale;
		$obj{'final'}->{$year}->{'aADR'}->{'ageAdjDRRESGHispanicFemale'} = $ageAdjDRRESGHispanicFemale;
		$obj{'final'}->{$year}->{'aADR'}->{'ageAdjDRRESGBlackMale'} = $ageAdjDRRESGBlackMale;
		$obj{'final'}->{$year}->{'aADR'}->{'ageAdjDRRESGBlackFemale'} = $ageAdjDRRESGBlackFemale;

		$obj{'final'}->{$year}->{'infants'}->{'infantDeathsBacterialSepsis'} = $infantDeathsBacterialSepsis;
		$obj{'final'}->{$year}->{'infants'}->{'infantDeathsCongenitalMalformations'} = $infantDeathsCongenitalMalformations;
		$obj{'final'}->{$year}->{'infants'}->{'infantDeathsCordComplication'} = $infantDeathsCordComplication;
		$obj{'final'}->{$year}->{'infants'}->{'infantDeathsLowBirthWeight'} = $infantDeathsLowBirthWeight;
		$obj{'final'}->{$year}->{'infants'}->{'infantDeathsMaternalComplication'} = $infantDeathsMaternalComplication;
		$obj{'final'}->{$year}->{'infants'}->{'infantDeathsPer100000Births'} = $infantDeathsPer100000Births;
		$obj{'final'}->{$year}->{'infants'}->{'infantDeathsSuddenDeathSyndrom'} = $infantDeathsSuddenDeathSyndrom;
		$obj{'final'}->{$year}->{'infants'}->{'infantDeathsUnintentionalInjuries'} = $infantDeathsUnintentionalInjuries;
		$obj{'final'}->{$year}->{'infants'}->{'infantDiseasesOfCirculatorySystem'} = $infantDiseasesOfCirculatorySystem;
		$obj{'final'}->{$year}->{'infants'}->{'infantNeonatalHemorrhage'} = $infantNeonatalHemorrhage;
		$obj{'final'}->{$year}->{'infants'}->{'infantRespiratoryDistress'} = $infantRespiratoryDistress;
	}

	# Then creating the unfinalized years objects.
	for my $year (sort{$a <=> $b} keys %{$yearlyValues{'provisional'}}) {
		my %rawObj = %{$yearlyValues{'provisional'}->{$year}};
		p%rawObj;

		my $globalDeaths                             = $rawObj{'globalDeaths'}                             // die;
		my $globCovid                                = $rawObj{'globCovid'}                                // die;
		my $ageAdjDRRESGTotal                        = $rawObj{'ageAdjDRRESGTotal'}                        // die;
		my $globAlzheimerCases                       = $rawObj{'globAlzheimerCases'}                       // die;
		my $globCovidCases                           = $rawObj{'globCovidCases'}                           // die;
		my $globDeathsCancerCases                    = $rawObj{'globDeathsCancerCases'}                    // die;
		my $globDeathsChronicRespiratoryDiseaseCases = $rawObj{'globDeathsChronicRespiratoryDiseaseCases'} // die;
		my $globDeathsHeartDiseaseCases              = $rawObj{'globDeathsHeartDiseaseCases'}              // die;
		my $globDiabetesCases                        = $rawObj{'globDiabetesCases'}                        // die;
		my $globInfluenzaAndPneumoniaCases           = $rawObj{'globInfluenzaAndPneumoniaCases'}           // die;
		my $globKidneyDiseaseCases                   = $rawObj{'globKidneyDiseaseCases'}                   // die;
		my $globStrokesCases                         = $rawObj{'globStrokesCases'}                         // die;
		my $globSuicideCases                         = $rawObj{'globSuicideCases'}                         // die;
		my $globUnintentionalInjuriesCases           = $rawObj{'globUnintentionalInjuriesCases'}           // die;
		my $infantDeathsPer100000Births              = $rawObj{'infantDeathsPer100000Births'}              // die;
		my $infantDeathsTotalCases                   = $rawObj{'infantDeathsTotalCases'}                   // die;
		$obj{'provisional'}->{$year}->{'global'}->{'globalDeaths'}                             = $globalDeaths;
		$obj{'provisional'}->{$year}->{'global'}->{'globAlzheimerCases'}                       = $globAlzheimerCases;
		$obj{'provisional'}->{$year}->{'global'}->{'globDiabetesCases'}                        = $globDiabetesCases;
		$obj{'provisional'}->{$year}->{'global'}->{'globKidneyDiseaseCases'}                   = $globKidneyDiseaseCases;
		$obj{'provisional'}->{$year}->{'global'}->{'globStrokesCases'}                         = $globStrokesCases;
		$obj{'provisional'}->{$year}->{'global'}->{'globSuicideCases'}                         = $globSuicideCases;
		$obj{'provisional'}->{$year}->{'global'}->{'globDeathsCancerCases'}                    = $globDeathsCancerCases;
		$obj{'provisional'}->{$year}->{'global'}->{'globDeathsChronicRespiratoryDiseaseCases'} = $globDeathsChronicRespiratoryDiseaseCases;
		$obj{'provisional'}->{$year}->{'global'}->{'globInfluenzaAndPneumoniaCases'}           = $globInfluenzaAndPneumoniaCases;
		$obj{'provisional'}->{$year}->{'global'}->{'globUnintentionalInjuriesCases'}           = $globUnintentionalInjuriesCases;
		$obj{'provisional'}->{$year}->{'global'}->{'globCovidCases'}                           = $globCovidCases;
		$obj{'provisional'}->{$year}->{'global'}->{'globDeathsHeartDiseaseCases'}              = $globDeathsHeartDiseaseCases;
		$obj{'provisional'}->{$year}->{'aADR'}->{'ageAdjDRRESGTotal'}                          = $ageAdjDRRESGTotal;
		$obj{'provisional'}->{$year}->{'infants'}->{'infantDeathsPer100000Births'}             = $infantDeathsPer100000Births;
		$obj{'provisional'}->{$year}->{'infants'}->{'infantDeathsTotalCases'}                  = $infantDeathsTotalCases;
	}
}

sub load_2021_values {
	open my $in, '<:utf8', $statsInFile;
	my $json;
	while (<$in>) {
		$json = $_;
	}
	close $in;
	$json = decode_json($json);
	my $merger = Hash::Merge->new();
	%obj = %{ $merger->merge( \%obj, \%$json ) };
	p%obj;
	die;
}

p%obj;
open my $out, '>:utf8', $statsOutFile;
my $json = encode_json\%obj;
print $out $json;
close $out;
# p%yearlyValues;
	# my $globCovid                           = $rawObj{'globCovid'}                           // die;
	# my $globCovidCases                      = $rawObj{'globCovidCases'}                      // die;
	# say "globCovid                           : $globCovid";
	# say "globCovidCases                      : $globCovidCases";