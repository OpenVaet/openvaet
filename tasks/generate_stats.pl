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
use JSON;
use FindBin;
use lib "$FindBin::Bin/../lib";

# Project's libraries.
use global;
use config;
use time;

# Executing data unification.
system("perl tasks/unify_data.pl");

# Sources to be updated.
my $ecdcSourceId = 1;
my $cdcSourceId  = 2;

# Initiating data which will contain the pre-categorized reports.
my %serious               = ();
my %deaths                = ();
my %nonSerious            = ();
my %eventsStats           = ();
my %substancesStats       = ();
my %eventsAdded           = ();

# Parsing & Integrating daily files.
my %vals = ();
parse_data();

print_reports();

p%vals;

sub parse_data {
	my @files = glob "unified_data/*/data.json";
	my ($currentFile, $totalFiles) = (0, 0);
	$totalFiles = scalar @files;
	for my $file (@files) {
		$currentFile++;
		STDOUT->printflush("\rParsing data - [$currentFile / $totalFiles]");
		my ($intDate) = $file =~ /unified_data\/(.*)\/data\.json/;
		open my $in, '<:utf8', $file;
		my $json;
		while (<$in>) {
			$json = $_;
		}
		close $in;
		if ($json) {
			$json = decode_json($json);
			parse_day($intDate, $json);
		}
	}
}

sub parse_day {
	my ($intDate, $json) = @_;
    my $reports = shift @$json;
    my @reports = @$reports;
    for my $reportData (@reports) {
    	my $source           = %$reportData{'source'}           // die;
    	my $patientDied      = %$reportData{'patientDied'}      // die;
    	my $yearName         = %$reportData{'yearName'}         // die;
    	my $reporterTypeName = %$reportData{'reporterTypeName'} // die;
    	my $ageGroupName     = %$reportData{'ageGroupName'}     // die;
    	my $sexName          = %$reportData{'sexName'}          // die;
    	my $statSection      = %$reportData{'statSection'}      // die;
    	my $isCovid          = %$reportData{'isCovid'}          // die;
    	my $isOtherVaccine   = %$reportData{'isOtherVaccine'}   // die;
    	my $seriousnessName  = %$reportData{'seriousnessName'}  // die;
    	my $reference        = %$reportData{'reference'}        // die;
    	# $vals{'patientDied'}->{$patientDied}->{$source}           = 1;
    	# $vals{'yearName'}->{$yearName}->{$source}           = 1;
    	# $vals{'seriousnessName'}->{$seriousnessName}->{$source}   = 1;
    	# $vals{'reporterTypeName'}->{$reporterTypeName}->{$source} = 1;
    	$vals{'statSection'}->{$statSection}->{$source} = 1;
    	# $vals{'sexName'}->{$sexName}->{$source} = 1;
    	die unless scalar @{%$reportData{'substances'}};
	    if ($patientDied == 1) {
	    	$eventsStats{'deaths'}->{$yearName}->{$reporterTypeName}->{$ageGroupName}->{$sexName}->{$statSection}++;
		} elsif ($seriousnessName eq 'Serious') {
	    	$eventsStats{'serious'}->{$yearName}->{$reporterTypeName}->{$ageGroupName}->{$sexName}->{$statSection}++;
		} else {
	    	$eventsStats{'nonSerious'}->{$yearName}->{$reporterTypeName}->{$ageGroupName}->{$sexName}->{$statSection}++;
		}
		my ($confirmedCovidCategory, $confirmedOthersCategory) = (0, 0);
	    for my $drugData (@{%$reportData{'substances'}}) {
	        my $substanceShortName = %$drugData{'substanceShortName'} // next;
	        my $substanceCategory = %$drugData{'substanceCategory'}   // die;
	        if ($substanceCategory eq 'COVID-19') {
	        	die unless $isCovid;
	        	$confirmedCovidCategory = 1;
	        } elsif ($substanceCategory eq 'OTHER') {
	        	die unless $isOtherVaccine;
	        	$confirmedOthersCategory = 1;
	        } else {
	        	die;
	        }
		    if ($patientDied == 1) {
		        unless (exists $eventsAdded{'referenceAndCategory'}->{$reference}->{$substanceCategory}) {
		        	$eventsAdded{'referenceAndCategory'}->{$reference}->{$substanceCategory} = 1;
		    		push @{$deaths{$yearName}->{$intDate}->{$substanceCategory}}, \%$reportData;
	    		}
		        unless (exists $eventsAdded{'globalStats'}->{$reference}->{$yearName}->{$reporterTypeName}->{$ageGroupName}->{$sexName}->{$substanceCategory}->{$substanceShortName}) {
		        	$eventsAdded{'globalStats'}->{$reference}->{$yearName}->{$reporterTypeName}->{$ageGroupName}->{$sexName}->{$substanceCategory}->{$substanceShortName} = 1;
	    			$substancesStats{'deaths'}->{$yearName}->{$reporterTypeName}->{$ageGroupName}->{$sexName}->{$substanceCategory}->{$substanceShortName}++;
	    		}
			} elsif ($seriousnessName eq 'Serious') {
		        unless (exists $eventsAdded{'referenceAndCategory'}->{$reference}->{$substanceCategory}) {
		        	$eventsAdded{'referenceAndCategory'}->{$reference}->{$substanceCategory} = 1;
	    			push @{$serious{$yearName}->{$intDate}->{$substanceCategory}}, \%$reportData;
	    		}
		        unless (exists $eventsAdded{'globalStats'}->{$reference}->{$yearName}->{$reporterTypeName}->{$ageGroupName}->{$sexName}->{$substanceCategory}->{$substanceShortName}) {
		        	$eventsAdded{'globalStats'}->{$reference}->{$yearName}->{$reporterTypeName}->{$ageGroupName}->{$sexName}->{$substanceCategory}->{$substanceShortName} = 1;
	    			$substancesStats{'serious'}->{$yearName}->{$reporterTypeName}->{$ageGroupName}->{$sexName}->{$substanceCategory}->{$substanceShortName}++;
	    		}
			} else {
		        # p%obj;
		        # die;
		        unless (exists $eventsAdded{'referenceAndCategory'}->{$reference}->{$substanceCategory}) {
		        	$eventsAdded{'referenceAndCategory'}->{$reference}->{$substanceCategory} = 1;
	    			push @{$nonSerious{$yearName}->{$intDate}->{$substanceCategory}}, \%$reportData;
	    		}
		        unless (exists $eventsAdded{'globalStats'}->{$reference}->{$yearName}->{$reporterTypeName}->{$ageGroupName}->{$sexName}->{$substanceCategory}->{$substanceShortName}) {
		        	$eventsAdded{'globalStats'}->{$reference}->{$yearName}->{$reporterTypeName}->{$ageGroupName}->{$sexName}->{$substanceCategory}->{$substanceShortName} = 1;
	    			$substancesStats{'nonSerious'}->{$yearName}->{$reporterTypeName}->{$ageGroupName}->{$sexName}->{$substanceCategory}->{$substanceShortName}++;
	    		}
			}
	    }
	    if ($isCovid) {
	    	unless ($confirmedCovidCategory) {
	    		p$reportData;
	    		die;
	    	}
	    }
	    if ($isOtherVaccine) {
	    	unless ($confirmedOthersCategory) {
	    		p$reportData;
	    		die;
	    	}
	    }
		# p$reportData;
		# die;
    }
}

sub print_reports {
	say "printing deaths abstract ...";
	my $statsFolder = 'stats';
	make_path($statsFolder) unless (-d $statsFolder);
	for my $year (sort{$a <=> $b} keys %deaths) {
		for my $intDate (sort{$a <=> $b} keys %{$deaths{$year}}) {
			for my $substanceCategory (sort keys %{$deaths{$year}->{$intDate}}) {
				my @obj = \@{$deaths{$year}->{$intDate}->{$substanceCategory}};
				# p@obj;
				make_path("$statsFolder/$year/$intDate/$substanceCategory") unless (-d "$statsFolder/$year/$intDate/$substanceCategory");
				open my $outDeaths, '>:utf8', "$statsFolder/$year/$intDate/$substanceCategory/deaths.json";
				my $deaths = encode_json\@obj;
				say $outDeaths $deaths;
				close $outDeaths;
			}
		}
	}

	say "printing serious abstract ...";
	for my $year (sort{$a <=> $b} keys %serious) {
		for my $intDate (sort{$a <=> $b} keys %{$serious{$year}}) {
			for my $substanceCategory (sort keys %{$serious{$year}->{$intDate}}) {
				my @obj = \@{$serious{$year}->{$intDate}->{$substanceCategory}};
				# p@obj;
				make_path("$statsFolder/$year/$intDate/$substanceCategory") unless (-d "$statsFolder/$year/$intDate/$substanceCategory");
				open my $outSerious, '>:utf8', "$statsFolder/$year/$intDate/$substanceCategory/serious.json";
				my $serious = encode_json\@obj;
				say $outSerious $serious;
				close $outSerious;
			}
		}
	}

	say "printing non-serious abstract ...";
	for my $year (sort{$a <=> $b} keys %nonSerious) {
		for my $intDate (sort{$a <=> $b} keys %{$nonSerious{$year}}) {
			for my $substanceCategory (sort keys %{$nonSerious{$year}->{$intDate}}) {
				my @obj = \@{$nonSerious{$year}->{$intDate}->{$substanceCategory}};
				# p@obj;
				make_path("$statsFolder/$year/$intDate/$substanceCategory") unless (-d "$statsFolder/$year/$intDate/$substanceCategory");
				open my $outNonSerious, '>:utf8', "$statsFolder/$year/$intDate/$substanceCategory/nonSerious.json";
				my $nonSerious = encode_json\@obj;
				say $outNonSerious $nonSerious;
				close $outNonSerious;
			}
		}
	}

	say "printing chart stats abstract ...";
	open my $outStats, '>:utf8', "$statsFolder/substance_stats.json";
	my $substancesStats = encode_json\%substancesStats;
	say $outStats $substancesStats;
	close $outStats;

	say "printing chart stats abstract ...";
	open my $outEventStats, '>:utf8', "$statsFolder/events_stats.json";
	my $eventsStats = encode_json\%eventsStats;
	say $outEventStats $eventsStats;
	close $outEventStats;
}