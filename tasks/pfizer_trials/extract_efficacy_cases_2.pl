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

# public/pfizer_documents/native_files/pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-lab-measurements.pdf
# page 586 to 602.

# This script parses these files, converts the PDF to HTML, then parses the HTML to convert it to a usable JSON format.

# We first parse the PDF file (which must be located here, which means that you must run tasks/pfizer_documents/get_documents.pl first).
my $casesPdfFile   = "public/pfizer_documents/native_files/pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-lab-measurements.pdf";
die "Missing source file, please run tasks/pfizer_documents/get_documents.pl first." unless -f $casesPdfFile;
my $casesPdfFolder = "raw_data/pfizer_trials/cases_efficacy_2";
my $outputFolder   = "public/doc/pfizer_trials";
make_path($outputFolder) unless (-d $outputFolder);

# If the pdf hasn't been extracted already, proceeding.
unless (-d $casesPdfFolder) {

	# Converts the Pfizer's PDFs to HTML.
	# You'll need the XPDF version corresponding to your OS.
	# Both files below are coming from https://www.xpdfreader.com/download.html
	# Windows : https://dl.xpdfreader.com/xpdf-tools-win-4.04.zip
	# Linux   : https://dl.xpdfreader.com/xpdf-tools-linux-4.04.tar.gz
	# Place the "pdftohtml.exe" (windows) or "pdftohtml" (linux) file,
	# located in the bin32/64 subfolder of the archive you downloaded,
	# in your project repository.
	my $pdfToHtmlExecutable = 'pdftohtml.exe'; # Either pdftohtml or pdftohtml.exe, depending on your OS.
	my $pdfToHtmlCommand     = "$pdfToHtmlExecutable \"$casesPdfFile\" \"$casesPdfFolder\"";
	system($pdfToHtmlCommand);
}

# We then verify that we have as expected 4376 HTML pages resulting from the extraction.
my %htmlPages = ();
verify_pdf_structure();

# We then extract pages 22 to 4376 (table "All Subjects").
my %patients = ();
my $totalPatients = 0;
extract_all_subjects_table();
say "total patients in this efficacy table : [$totalPatients]";

# Prints patients JSON.
open my $out, '>:utf8', "$outputFolder/pfizer_trial_efficacy_cases_2.json";
print $out encode_json\%patients;
close $out;

# Prints patients CSV.
open my $out2, '>:utf8', "$outputFolder/pfizer_trial_efficacy_cases_1.csv";
say $out2 "Source File;Page Number;Entry Number;Subject Id;Central Lab Result;Symptoms Start Date;";
for my $subjectId (sort keys %patients) {
	my $symptomstartDate = $patients{$subjectId}->{'symptomstartDate'} // die;
	my $swabResult       = $patients{$subjectId}->{'swabResult'}       // die;
	my $pageNum          = $patients{$subjectId}->{'pageNum'}          // die;
	my $entryNum         = $patients{$subjectId}->{'entryNum'}         // die;
	say $out2 "pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-lab-measurements-sensitive.pdf;$pageNum;$entryNum;$subjectId;$swabResult;$symptomstartDate;";

}
close $out2;

sub verify_pdf_structure {
	for my $htmlFile (glob "$casesPdfFolder/*") {
		next unless $htmlFile =~ /\/page.*\.html/;
		my ($pageNum) = $htmlFile =~ /\/page(.*)\.html/;
		$htmlPages{$pageNum} = 1;
	}
	unless (keys %htmlPages == 671) {
		die "Something went wrong during PDF extraction. Please verify your PDF file & that XPDF is properly configured.";
	}
}

sub extract_all_subjects_table {
	for my $pageNum (sort{$a <=> $b} keys %htmlPages) {
		next unless $pageNum >= 586;
		my $htmlFile = "$casesPdfFolder/page$pageNum.html";
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

		# We first extract all the patient ids in the page, so we known how many to expect.
		my %patientsIds        = parse_patients_ids(@divs);
		my $pageTotalPatients  = keys %patientsIds;
		die unless $pageTotalPatients;

		# We then look for symptoms dates & swab dates.
		my %casesDates = parse_cases_dates($pageTotalPatients, @divs);

		for my $topMargin (sort{$a <=> $b} keys %patientsIds) {
			$totalPatients++;
			my $subjectId              = $patientsIds{$topMargin}->{'subjectId'}                     // die;
			my $entryNum               = $patientsIds{$topMargin}->{'entryNum'}                      // die;
			die if exists $patients{$subjectId};
			$patients{$subjectId}->{'pageNum'}  = $pageNum;
			$patients{$subjectId}->{'entryNum'} = $entryNum;

			# Locates next patient top margin.
			my $nextTopMargin;
			for my $nTM (sort{$a <=> $b} keys %patientsIds) {
				next if $nTM <= $topMargin;
				$nextTopMargin = $nTM;
				last;
			}

			# For each entry equal or inferior to next patient margin, we locate the start, stop dates of the symptoms, and the swab date & results.
			# say "topMargin     : $topMargin";
			# say "nextTopMargin : $nextTopMargin";
			my ($symptomstartDate, $swabResult);
			for my $tM (sort{$a <=> $b} keys %casesDates) {
				next if $tM < $topMargin;
				if ($nextTopMargin) {
					last if $tM >= $nextTopMargin;
				}
				$symptomstartDate = $casesDates{$tM}->{'casesDate'} // die;
				$swabResult = $casesDates{$tM}->{'swabResult'} // die;
				last if $swabResult =~ /Pos/;
			}
			$patients{$subjectId}->{'symptomstartDate'} = $symptomstartDate;
			$patients{$subjectId}->{'swabResult'}       = $swabResult;
		}
		last if $pageNum == 602;
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
					}
					my $style = $div->attr_get_i('style');
					($topMargin) = $style =~ /top:(.*)px;/;
					die unless looks_like_number $topMargin;
					$trialData = $word;
					$init++;
				} elsif ($word =~ /^\d\d\d\d$/) {
					die unless $trialData && !$siteData;
					$siteData = $word;
				} else {
					if ($trialData && $siteData) {
						my $subjectId = "$trialData $siteData $word";
						$subjectId =~ s/\^//;
						unless (length $subjectId == 22) {
							$subjectId =~ s/†//;
							unless (length $subjectId == 22) {
								($subjectId) = split ' \(', $subjectId;
								die "subjectId : [$subjectId]" unless (length $subjectId == 22);
							}
						}
						$entryNum++;
						$patientsIds{$topMargin}->{'entryNum'}           = $entryNum;
						$patientsIds{$topMargin}->{'subjectId'}          = $subjectId;
						$patientsIds{$topMargin}->{'subjectIdTopMargin'} = $topMargin;
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

sub parse_cases_dates {
	my ($pageTotalPatients, @divs) = @_;
	my %casesDates = ();
	my ($dNum, $entryNum) = (0, 0);

	# The date has two possible formats ; date alone, or age group & date collated.
	for my $div (@divs) {
		my $text = $div->as_trimmed_text;
		last if $text =~ /Abbreviations:/;
		$dNum++;
		my @words = split ' ', $text;
		for my $word (@words) {
			if ((
					(
						$word =~ /^.....2020$/ ||
						$word =~ /^\(.....2020\)$/ ||
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
						$word =~ /^\(.....2021\)$/ ||
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
				my ($date) = $word =~ /(.....2020)/;
				unless ($date) {
					($date) = $word =~ /(.....2021)/;
				}
				die unless $date;
				my ($casesDate, $casesYear, $casesMonth, $casesWeekNumber) = convert_date($date);
				$entryNum++;
				my $style = $div->attr_get_i('style');
				my ($topMargin) = $style =~ /top:(.*)px;/;
				die unless looks_like_number $topMargin;
				$casesDates{$topMargin}->{'casesDate'}          = $casesDate;
				$casesDates{$topMargin}->{'casesYear'}          = $casesYear;
				$casesDates{$topMargin}->{'casesMonth'}         = $casesMonth;
				$casesDates{$topMargin}->{'casesWeekNumber'}    = $casesWeekNumber;
			} elsif ($word =~ /Pos/ || $word =~ /Neg/) {
				my $style = $div->attr_get_i('style');
				my ($topMargin) = $style =~ /top:(.*)px;/;
				die unless looks_like_number $topMargin;
				$entryNum++;
				$casesDates{$topMargin}->{'swabResult'}         = $word;
			}
		}
	}
	return %casesDates;
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