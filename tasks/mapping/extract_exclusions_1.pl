#!/usr/bin/perl
use strict;
use warnings;
use v5.26;
use Data::Dumper;
use Data::Printer;
binmode STDOUT, ":utf8";
no autovivification;
use utf8;
use JSON;
use HTTP::Cookies;
use HTML::Tree;
use LWP::UserAgent;
use LWP::Simple;
use File::stat;
use Date::DayOfWeek;
use Date::WeekNumber qw/ iso_week_number /;
use Scalar::Util qw(looks_like_number);
use File::Path qw(make_path);
use Math::Round qw(nearest);

# Exclusions are stored in
# https://openvaet.org/pfizearch/viewer?pdf=pfizer_documents/native_files/pd-production-070122/125742_S1_M5_5351_c4591001-interim-mth6-discontinued-patients.pdf&currentLanguage=en
# This script parses these files, converts the PDF to HTML, then parses the HTML to convert it to a usable JSON format.

# We first parse the PDF file (which must be located here, which means that you must run tasks/pfizer_documents/get_documents.pl first).
my $exclusionsPdfFile   = "public/pfizer_documents/native_files/pd-production-070122/125742_S1_M5_5351_c4591001-interim-mth6-discontinued-patients.pdf";
die "Missing source file, please run tasks/pfizer_documents/get_documents.pl first." unless -f $exclusionsPdfFile;
my $exclusionsPdfFolder = "raw_data/pfizer_trials/exclusions";
my $outputFolder        = "raw_data/pfizer_trials/exclusions_output_1";
make_path($outputFolder) unless (-d $outputFolder);

# If the pdf hasn't been extracted already, proceeding.
unless (-d $exclusionsPdfFolder) {

	# Converts the Pfizer's PDFs to HTML.
	# You'll need the XPDF version corresponding to your OS.
	# Both files below are coming from https://www.xpdfreader.com/download.html
	# Windows : https://dl.xpdfreader.com/xpdf-tools-win-4.04.zip
	# Linux   : https://dl.xpdfreader.com/xpdf-tools-linux-4.04.tar.gz
	# Place the "pdftohtml.exe" (windows) or "pdftohtml" (linux) file,
	# located in the bin32/64 subfolder of the archive you downloaded,
	# in your project repository.
	my $pdfToHtmlExecutable = 'pdftohtml.exe'; # Either pdftohtml or pdftohtml.exe, depending on your OS.
	my $pdfToHtmlCommand     = "$pdfToHtmlExecutable \"$exclusionsPdfFile\" \"$exclusionsPdfFolder\"";
	system($pdfToHtmlCommand);
}

# We then verify that we have as expected 4376 HTML pages resulting from the extraction.
my %htmlPages = ();
verify_pdf_structure();

# We then extract pages 22 to 4376 (table "All Subjects").
my %patients = ();
my $totalPatients = 0;
extract_all_exclusions_tables();
# p%patients;
say "totalPatients   : $totalPatients";

# Prints patients JSON.
open my $out3, '>:utf8', "$outputFolder/pfizer_trial_exclusions.json";
print $out3 encode_json\%patients;
close $out3;

sub verify_pdf_structure {
	for my $htmlFile (glob "$exclusionsPdfFolder/*") {
		next unless $htmlFile =~ /\/page.*\.html/;
		my ($pageNum) = $htmlFile =~ /\/page(.*)\.html/;
		$htmlPages{$pageNum} = 1;
	}
	unless (keys %htmlPages == 232) {
		die "Something went wrong during PDF extraction. Please verify your PDF file & that XPDF is properly configured.";
	}
}

sub extract_all_exclusions_tables {
	for my $pageNum (sort{$a <=> $b} keys %htmlPages) {
		my $htmlFile = "$exclusionsPdfFolder/page$pageNum.html";
		say "htmlFile : $htmlFile";
		my $content;
		open my $in, '<:utf8', $htmlFile;
		while (<$in>) {
			$content .= $_;
		}
		close $in;
		die unless $content;
		my $tree = HTML::Tree->new();
		$tree->parse($content);
		my $body = $tree->find('body');
		my @divs = $body->find('div');

		open my $out, '>:utf8', 'tmp.html';
		print $out $content;
		close $out;

		# We first extract all the patient ids in the page, so we known how many to expect.
		my %patientsIds        = parse_patients_ids(@divs);
		my $pageTotalPatients  = keys %patientsIds;
		die unless $pageTotalPatients;
		# p%patientsIds;

		# We then look for exclusions dates.
		my %exclusionsDates = parse_exclusions_dates($pageTotalPatients, @divs);
		# p%exclusionsDates;

		# Integrates latest exclusion dates.
		for my $topMargin (sort{$a <=> $b} keys %patientsIds) {
			my $nextTopMargin;
			for my $nTM (sort{$a <=> $b} keys %patientsIds) {
				next if $nTM <= $topMargin;
				$nextTopMargin = $nTM;
				last;
			}
			$totalPatients++;
			my $patientId = $patientsIds{$topMargin}->{'patientId'} // die;
			my $entryNum  = $patientsIds{$topMargin}->{'entryNum'}  // die;
			for my $tM (sort{$a <=> $b} keys %exclusionsDates) {
				next if $tM < $topMargin;
				if ($nextTopMargin) {
					last if $tM >= $nextTopMargin;
				}
				my $exclusionsDate       = $exclusionsDates{$tM}->{'exclusionsDate'}       // die;
				my $exclusionsMonth      = $exclusionsDates{$tM}->{'exclusionsMonth'}      // die;
				my $exclusionsWeekNumber = $exclusionsDates{$tM}->{'exclusionsWeekNumber'} // die;
				my $exclusionsYear       = $exclusionsDates{$tM}->{'exclusionsYear'}       // die;
				$patients{$patientId}->{'exclusionsDate'}       = $exclusionsDate;
				$patients{$patientId}->{'exclusionsMonth'}      = $exclusionsMonth;
				$patients{$patientId}->{'exclusionsWeekNumber'} = $exclusionsWeekNumber;
				$patients{$patientId}->{'exclusionsYear'}       = $exclusionsYear;
			}
			die "patientId : $patientId, no date found" unless keys %{$patients{$patientId}};
		}
		last if $pageNum == 229;
	}
}

sub parse_patients_ids {
	my @divs = @_;
	my %patientsIds = ();
	my ($dNum, $entryNum, $init) = (0, 0, 0);
	my ($trialData, $siteData, $topMargin);
	for my $div (@divs) {
		my $text = $div->as_trimmed_text;
		last if $text =~ /Note:/;
		$dNum++;
		# say "$dNum | $text";
		if (($text =~ /C4591001/ || $text =~ /^\d\d\d\d$/ || $text =~ /\d\d\d\d\d\d\d\d/)) {
			my @words = split ' ', $text;
			for my $word (@words) {
				if ($word =~ /C4591001/) {
					unless ($word =~ /^C\d\d\d\d\d\d\d$/) {
						($word) = 'C4591001';
						# say "word : $word";
						# die;
					}
					my $style = $div->attr_get_i('style');
					($topMargin) = $style =~ /top:(.*)px;/;
					die unless looks_like_number $topMargin;
					$trialData = $word;
					$init++;
					# say "trialData : $trialData";
					# say "topMargin : $topMargin";
					# die;
				} elsif ($word =~ /^\d\d\d\d$/) {
					die unless $trialData && !$siteData;
					$siteData = $word;
					# say "siteData  : $siteData";
					# die;
				} else {
					if ($trialData && $siteData) {
						my $patientId = "$trialData $siteData $word";
						$patientId =~ s/\^//;
						unless (length $patientId == 22) {
							$patientId =~ s/†//;
							unless (length $patientId == 22) {
								($patientId) = split ' \(', $patientId;
								# say "patientId : [$patientId]";
								die "patientId : [$patientId]" unless (length $patientId == 22);
							}
						}
						# die;
						$entryNum++;
						$patientsIds{$topMargin}->{'entryNum'}           = $entryNum;
						$patientsIds{$topMargin}->{'patientId'}          = $patientId;
						$patientsIds{$topMargin}->{'patientIdTopMargin'} = $topMargin;
						# say "$entryNum | $patientId";
						$trialData = undef;
						$siteData  = undef;
						$topMargin = undef;
					}
				}
			}
		}
	}
	return %patientsIds;
}

sub parse_exclusions_dates {
	my ($pageTotalPatients, @divs) = @_;
	my %exclusionsDates = ();
	my ($dNum, $entryNum) = (0, 0);

	# The date has two possible formats ; date alone, or age group & date collated.
	for my $div (@divs) {
		my $text = $div->as_trimmed_text;
		last if $text =~ /Note:/;
		$dNum++;
		my @words = split ' ', $text;
		for my $word (@words) {
			# say "$dNum | $text";
			if ((
					(
						$word =~ /^.....2020$/ ||
						(
							$word =~ /^..-.. .....2020$/ ||
							$word =~ />.. .....2020$/
						) ||
						(
							$word =~ /^^..-.. .....2020 \d\d\d\d\d\d/ ||
							$word =~ />.. .....2020 \d\d\d\d\d\d/
						)
					) ||
					(
						$word =~ /^.....2021$/ ||
						(
							$word =~ /^..-.. .....2021$/ ||
							$word =~ />.. .....2021$/
						) ||
						(
							$word =~ /^^..-.. .....2021 \d\d\d\d\d\d/ ||
							$word =~ />.. .....2021 \d\d\d\d\d\d/
						)
					)
				) && $word !~ /Page/) {
				# say "$dNum | $word";
				my ($date) = $word =~ /(.....2020)/;
				unless ($date) {
					($date) = $word =~ /(.....2021)/;
				}
				die unless $date;
				$entryNum++;
				my $style = $div->attr_get_i('style');
				# say "style : $style";
				my ($topMargin) = $style =~ /top:(.*)px;/;
				my ($leftMargin) = $style =~ /left:(.*)px; top:/;
				# say "topMargin  : $topMargin";
				# say "leftMargin : $leftMargin";
				# say "word       : $word";
				die unless looks_like_number $topMargin;
				die unless looks_like_number $leftMargin;
				next unless $leftMargin > 120 && $leftMargin < 250;
				my ($exclusionsDate, $exclusionsYear, $exclusionsMonth, $exclusionsWeekNumber) = convert_date($date);
				$exclusionsDates{$topMargin}->{'exclusionsDateTopMargin'} = $topMargin;
				$exclusionsDates{$topMargin}->{'exclusionsDate'}          = $exclusionsDate;
				$exclusionsDates{$topMargin}->{'exclusionsYear'}          = $exclusionsYear;
				$exclusionsDates{$topMargin}->{'exclusionsMonth'}         = $exclusionsMonth;
				$exclusionsDates{$topMargin}->{'exclusionsWeekNumber'}    = $exclusionsWeekNumber;
				# say "$dNum | $exclusionsDate";
			}
		}
	}
	return %exclusionsDates;
}

sub convert_date {
	my $dt = shift;
	my ($d, $m, $y) = $dt =~ /(..)(...)(....)/;
	$m = convert_month($m);
	my $weekNumber = iso_week_number("$y-$m-$d");
	(undef, $weekNumber) = split '-', $weekNumber;
	$weekNumber =~ s/W//;
	return ("$y$m$d", $y, $m, $weekNumber);
}

sub convert_month {
	my $m = shift;
	$m = uc $m;
	return '01' if $m eq 'JAN';
	return '02' if $m eq 'FEB';
	return '03' if $m eq 'MAR';
	return '04' if $m eq 'APR';
	return '05' if $m eq 'MAY';
	return '06' if $m eq 'JUN';
	return '07' if $m eq 'JUL';
	return '08' if $m eq 'AUG';
	return '09' if $m eq 'SEP';
	return '10' if $m eq 'OCT';
	return '11' if $m eq 'NOV';
	return '12' if $m eq 'DEC';
	die "failed to convert month [$m]";
}