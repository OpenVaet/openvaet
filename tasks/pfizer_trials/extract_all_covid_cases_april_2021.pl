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

# Original cases files of the patients is here,page 1 to 65, finalized on November 24, 2020, "Listing of Subjects With Postvaccination SARS-CoV-2 NAAT-Positive Nasal Swab and COVID-19 Signs and Symptoms – Dose 1 All-Available Efficacy Population"
# https://openvaet.org/pfizearch/viewer?pdf=pfizer_documents/native_files/pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-lab-measurements-sensitive.pdf&currentLanguage=en

# Another file of interest is https://openvaet.org/pfizearch/pdf_search_details?fileShort=pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-lab-measurements.pdf&fileMd5=853a60a8850b3d52571c55de8d863225&terms=shortness%20of%20breath&allTermsOnly=true&currentLanguage=fr
# 16.2.8.1.IA1 Listing of Subjects With Postvaccination SARS-CoV-2 NAAT-Positive Nasal Swab and COVID-19 Signs and Symptoms – Dose 1 All-Available Efficacy Population – Interim Analysis 1
# Finalized on December 2, 2020, page 1 to 38.

# Another file, page 1 to 225, finalized on April 1, 2021, "Listing of Subjects With First COVID-19 Occurrence After Dose 1 – Blinded Placebo-Controlled Follow-up Period – Dose 1 All-Available Efficacy Population"
# https://openvaet.org/pfizearch/viewer?pdf=pfizer_documents/native_files/pd-production-070122/125742_S1_M5_5351_c4591001-interim-mth6-lab-measurements-sensitive.pdf&currentLanguage=en
# There seems to be the exact same file on https://openvaet.org/pfizearch/pdf_search_details?fileShort=pd-production-070122/125742_S1_M5_5351_c4591001-interim-mth6-lab-measurements-sensitive.pdf&fileMd5=31a4337f663a96dfc5db9df2b5d480c8&terms=shortness%20of%20breath&allTermsOnly=true&currentLanguage=fr

# This script parses these files, converts the PDF to HTML, then parses the HTML to convert it to a usable JSON format.

# We first parse the PDF file (which must be located here, which means that you must run tasks/pfizer_documents/get_documents.pl first).
my $casesPdfFile   = "public/pfizer_documents/native_files/pd-production-070122/125742_S1_M5_5351_c4591001-interim-mth6-lab-measurements-sensitive.pdf";
die "Missing source file, please run tasks/pfizer_documents/get_documents.pl first." unless -f $casesPdfFile;
my $casesPdfFolder = "raw_data/pfizer_trials/cases_042021";
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
# p%patients;
say "totalPatients   : $totalPatients";

# Prints patients JSON.
open my $out3, '>:utf8', "$outputFolder/pfizer_trial_positive_cases_april_2021.json";
print $out3 encode_json\%patients;
close $out3;

sub verify_pdf_structure {
	for my $htmlFile (glob "$casesPdfFolder/*") {
		next unless $htmlFile =~ /\/page.*\.html/;
		my ($pageNum) = $htmlFile =~ /\/page(.*)\.html/;
		$htmlPages{$pageNum} = 1;
	}
	unless (keys %htmlPages == 430) {
		die "Something went wrong during PDF extraction. Please verify your PDF file & that XPDF is properly configured.";
	}
}

sub extract_all_subjects_table {
	my $processedRows = 0;
	my $labConflicts = 0;
	my $priorNov14 = 0;
	my $localLabKnown = 0;
	for my $pageNum (sort{$a <=> $b} keys %htmlPages) {
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

		# open my $out, '>:utf8', 'tmp.html';
		# print $out $content;
		# close $out;

		# We first extract all the patient ids in the page, so we known how many to expect.
		my %patientsIds        = parse_patients_ids(@divs);
		my $pageTotalPatients  = keys %patientsIds;
		die unless $pageTotalPatients;
		# p%patientsIds;

		# We then look for symptoms dates & swab dates.
		my %casesDates = parse_cases_dates($pageTotalPatients, @divs);

		# Fetching first swabs diagnoses.
		my %firstSwabs = parse_swabs($pageTotalPatients, @divs);
		# p%casesDates;

		# # We then look for the cases groups.
		# my %casesData  = parse_cases_groups($pageNum, $pageTotalPatients, @divs);
		# # p%patientsIds;
		# p%casesDates;
		# die;
		# # p%casesData;

		for my $topMargin (sort{$a <=> $b} keys %patientsIds) {
			$totalPatients++;
			my $uSubjectId              = $patientsIds{$topMargin}->{'uSubjectId'}                     // die;
			my ($subjectId) = $uSubjectId =~ /^C\d\d\d\d\d\d\d \d\d\d\d (\d\d\d\d\d\d\d\d)/;
			die unless $subjectId;
			my $entryNum               = $patientsIds{$topMargin}->{'entryNum'}                      // die;
			die if exists $patients{$uSubjectId};
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
			my ($symptomstartDate, $symptomsEndDate, $visit1Tests, $centralLabTest, $localLabTest, $swabDate);
			for my $tM (sort{$a <=> $b} keys %casesDates) {
				next if $tM < $topMargin;
				if ($nextTopMargin) {
					last if $tM >= $nextTopMargin;
				}
				my $totalEntries = keys %{$casesDates{$tM}};
				unless ($totalEntries == 5) {
					if ($totalEntries == 4) {

						# We verify that we have one date, then 2 sets of swab results, then one date.
						my $expectLabelConflict = 0;
						my $elemNum = 0;
						for my $eN (sort{$a <=> $b} keys %{$casesDates{$tM}}) {
							$elemNum++;
							if ($elemNum == 1 || $elemNum == 4) {
								unless (exists $casesDates{$tM}->{$eN}->{'casesDate'}) {
									# say "Likely another format, such as multiple tests ?";
									# p$casesDates{$tM};
									$expectLabelConflict = 1;
									# die;
								}
							} else {
								unless (exists $casesDates{$tM}->{$eN}->{'swabResult'}) {
									p$casesDates{$tM};
									die;
								}
							}
						}
						if ($expectLabelConflict) {
							# say "Likely another format, such as multiple tests with no end date x_x";
							# p$casesDates{$tM};
							my $elemNum = 0;
							for my $eN (sort{$a <=> $b} keys %{$casesDates{$tM}}) {
								$elemNum++;
								if ($elemNum == 1) {
									unless (exists $casesDates{$tM}->{$eN}->{'casesDate'}) {
										die;
									}
								} else {
									unless (exists $casesDates{$tM}->{$eN}->{'swabResult'}) {
										p$casesDates{$tM};
										die;
									}
								}
							}
							my $nextTM;
							for my $nTM (sort{$a <=> $b} keys %casesDates) {
								next if $nTM <= $tM;
								$nextTM = $nTM;
								last;
							}
							die unless keys %{$casesDates{$nextTM}} == 1;
							for my $eN (sort{$a <=> $b} keys %{$casesDates{$nextTM}}) {
								unless (exists $casesDates{$nextTM}->{$eN}->{'casesDate'}) {
									die;
								}
							}
							# say "nextTM : $nextTM";
							# p$casesDates{$nextTM};
							# die;
							$elemNum = 0;
							for my $eN (sort{$a <=> $b} keys %{$casesDates{$tM}}) {
								$elemNum++;
								if ($elemNum == 1) {
									$symptomstartDate = $casesDates{$tM}->{$eN}->{'casesDate'} // die;
								} elsif ($elemNum == 2) {
									$visit1Tests = $casesDates{$tM}->{$eN}->{'swabResult'} // die;
								} elsif ($elemNum == 3) {
									$centralLabTest = $casesDates{$tM}->{$eN}->{'swabResult'} // die;
								} elsif ($elemNum == 4) {
									$localLabTest = $casesDates{$tM}->{$eN}->{'swabResult'} // die;
								}
							}
							for my $eN (sort{$a <=> $b} keys %{$casesDates{$nextTM}}) {
								$swabDate = $casesDates{$nextTM}->{$eN}->{'casesDate'} // die;
							}
							# say "A row with local & central & no end date -> $symptomstartDate, $visit1Tests, $centralLabTest != $localLabTest, $swabDate";
							$processedRows++;
							last if $centralLabTest =~ /Pos/;
							# die;
						} else {
							my $elemNum = 0;
							for my $eN (sort{$a <=> $b} keys %{$casesDates{$tM}}) {
								$elemNum++;
								if ($elemNum == 1 || $elemNum == 4) {
									unless (exists $casesDates{$tM}->{$eN}->{'casesDate'}) {
										die;
									}
								} else {
									unless (exists $casesDates{$tM}->{$eN}->{'swabResult'}) {
										p$casesDates{$tM};
										die;
									}
								}
							}
							$elemNum = 0;
							for my $eN (sort{$a <=> $b} keys %{$casesDates{$tM}}) {
								$elemNum++;
								if ($elemNum == 1) {
									$symptomstartDate = $casesDates{$tM}->{$eN}->{'casesDate'} // die;
								} elsif ($elemNum == 2) {
									$visit1Tests = $casesDates{$tM}->{$eN}->{'swabResult'} // die;
								} elsif ($elemNum == 3) {
									$centralLabTest = $casesDates{$tM}->{$eN}->{'swabResult'} // die;
								} elsif ($elemNum == 4) {
									$swabDate = $casesDates{$tM}->{$eN}->{'casesDate'} // die;
								}
							}
							$processedRows++;
							# say "A row with central only & no end date -> $symptomstartDate, $visit1Tests, $centralLabTest, $swabDate";
							last if $centralLabTest =~ /Pos/;
							# p$casesDates{$tM};
							# die;
						}
					} elsif ($totalEntries == 1) {
						# Let's care about covid duration later as we already know the data will be altered.
						# say "Another positive swab date ?";
						# for my $eN (sort{$a <=> $b} keys %{$casesDates{$tM}}) {
						# 	unless (exists $casesDates{$tM}->{$eN}->{'casesDate'}) {
						# 		die;
						# 	}
						# }
						# p$casesDates{$tM};
					} else {
						p$casesDates{$tM};
						say "tM : $tM";
						die "totalEntries : $totalEntries";
					}
				} else {
					my $elemNum = 0;
					my $likelyLabConflict = 0;
					for my $eN (sort{$a <=> $b} keys %{$casesDates{$tM}}) {
						$elemNum++;
						if ($elemNum == 1 || $elemNum == 2 || $elemNum == 5) {
							unless (exists $casesDates{$tM}->{$eN}->{'casesDate'}) {
								# say "Probably a conflict between lab results";
								# p$casesDates{$tM};
								# die;
								$likelyLabConflict = 1;
							}
						} else {
							unless (exists $casesDates{$tM}->{$eN}->{'swabResult'}) {
								p$casesDates{$tM};
								die;
							}
						}
					}
					if ($likelyLabConflict == 1) {
						# say "Probably a conflict between lab results, we should find a date floating alone on next tM. Current : [$tM]";
						# p$casesDates{$tM};
						my $nextTM;
						for my $nTM (sort{$a <=> $b} keys %casesDates) {
							next if $nTM <= $tM;
							$nextTM = $nTM;
							last;
						}
						die unless keys %{$casesDates{$nextTM}} == 1;
						for my $eN (sort{$a <=> $b} keys %{$casesDates{$nextTM}}) {
							unless (exists $casesDates{$nextTM}->{$eN}->{'casesDate'}) {
								die;
							}
						}
						# say "nextTM : $nextTM";
						# p$casesDates{$nextTM};
						my $elemNum = 0;
						for my $eN (sort{$a <=> $b} keys %{$casesDates{$tM}}) {
							$elemNum++;
							if ($elemNum == 1) {
								$symptomstartDate = $casesDates{$tM}->{$eN}->{'casesDate'} // die;
							} elsif ($elemNum == 2) {
								$symptomsEndDate = $casesDates{$tM}->{$eN}->{'casesDate'} // die;
							} elsif ($elemNum == 3) {
								$visit1Tests = $casesDates{$tM}->{$eN}->{'swabResult'} // die;
							} elsif ($elemNum == 4) {
								$localLabTest = $casesDates{$tM}->{$eN}->{'swabResult'} // die;
							} elsif ($elemNum == 5) {
								$centralLabTest = $casesDates{$tM}->{$eN}->{'swabResult'} // die;
							}
						}
						for my $eN (sort{$a <=> $b} keys %{$casesDates{$nextTM}}) {
							$swabDate = $casesDates{$nextTM}->{$eN}->{'casesDate'} // die;
						}
						# say "A conflict between labs row -> $symptomstartDate, $symptomsEndDate, $visit1Tests, $centralLabTest != $localLabTest, $swabDate";
						$processedRows++;
						last if $centralLabTest =~ /Pos/;
					} else {
						my $elemNum = 0;
						for my $eN (sort{$a <=> $b} keys %{$casesDates{$tM}}) {
							$elemNum++;
							if ($elemNum == 1) {
								$symptomstartDate = $casesDates{$tM}->{$eN}->{'casesDate'} // die;
							} elsif ($elemNum == 2) {
								$symptomsEndDate = $casesDates{$tM}->{$eN}->{'casesDate'} // die;
							} elsif ($elemNum == 3) {
								$visit1Tests = $casesDates{$tM}->{$eN}->{'swabResult'} // die;
							} elsif ($elemNum == 4) {
								$centralLabTest = $casesDates{$tM}->{$eN}->{'swabResult'} // die;
							} elsif ($elemNum == 5) {
								$swabDate = $casesDates{$tM}->{$eN}->{'casesDate'} // die;
							}
						}
						# say "A really normal row -> $symptomstartDate, $symptomsEndDate, $visit1Tests, $centralLabTest, $swabDate";
						$processedRows++;
						last if $centralLabTest =~ /Pos/;
					}

					# say "Normal row.";
					# p$casesDates{$tM};
					# die;
				}
				# p$casesDates{$tM};
			}
			die unless $symptomstartDate && $swabDate;
			die unless $centralLabTest =~ /Pos/;
			my ($visit1NBindAssay, $visit1NaaT, $visit2NaaT) = $visit1Tests =~ /(.*)\/(.*)\/(.*)/;
			die unless $visit1NBindAssay && $visit1NaaT && $visit2NaaT;
			die unless $visit1NBindAssay eq 'Pos' || $visit1NBindAssay eq 'Neg' || $visit1NBindAssay eq 'Unk';
			die unless $visit1NaaT eq 'Pos' || $visit1NaaT eq 'Neg' || $visit1NaaT eq 'Unk';
			die unless $visit2NaaT eq 'Pos' || $visit2NaaT eq 'Neg' || $visit2NaaT eq 'Unk';
			die unless $centralLabTest =~ /Pos/;
			if ($localLabTest) {
				die unless $localLabTest =~ /Pos/ || $localLabTest =~ /Neg/;
				if ($localLabTest =~ /Neg/) {
					$localLabTest = 'Neg';
				} else {
					$localLabTest = 'Pos';
				}
				$labConflicts++ if $localLabTest eq 'Neg';
				$localLabKnown++;
			}
			unless (exists $patients{$subjectId}->{'swabDate'}) {
				if ($swabDate <= 20201114) {
					$priorNov14++;
				}
			}
			$centralLabTest = 'Pos';
			$patients{$subjectId}->{'uSubjectId'} = $uSubjectId;
			$patients{$subjectId}->{'uSubjectIds'}->{$uSubjectId} = 1;
			$patients{$subjectId}->{'symptomstartDate'} = $symptomstartDate;
			$patients{$subjectId}->{'symptomsEndDate'} = $symptomsEndDate;
			$patients{$subjectId}->{'centralLabTest'} = $centralLabTest;
			$patients{$subjectId}->{'localLabTest'} = $localLabTest;
			$patients{$subjectId}->{'swabDate'} = $swabDate;
			$patients{$subjectId}->{'visit1NBindAssay'} = $visit1NBindAssay;
			$patients{$subjectId}->{'visit1NaaT'} = $visit1NaaT;
			$patients{$subjectId}->{'visit2NaaT'} = $visit2NaaT;
			# p%patients;
			# die;
			# say "$subjectId - $symptomstartDate, $symptomsEndDate, $centralLabTest, $swabDate -> $visit1NBindAssay, $visit1NaaT, $visit2NaaT";
		}
		last if $pageNum == 224;
	}
	say "processedRows : $processedRows";
	say "localLabKnown : $localLabKnown";
	say "labConflicts : $labConflicts";
	say "priorNov14 : $priorNov14";
}

sub parse_patients_ids {
	my @divs = @_;
	my %patientsIds = ();
	my ($dNum, $entryNum, $init) = (0, 0, 0);
	my ($trialAndSiteData, $topMargin);
	for my $div (@divs) {
		my $text = $div->as_trimmed_text;
		last if $text =~ /Abbreviations:/;
		$dNum++;
		# say "$dNum | $text";
		if (($text =~ /C4591001/ || $text =~ /\d\d\d\d\d\d\d\d/)) {
			if ($text =~ /C4591001/) {
				# say "text : $text";
				unless ($text =~ /^C\d\d\d\d\d\d\d \d\d\d\d$/) {
					($text) = $text =~ /(C\d\d\d\d\d\d\d \d\d\d\d)/;
					die unless $text;
				}
				my $style = $div->attr_get_i('style');
				($topMargin) = $style =~ /top:(.*)px;/;
				die unless looks_like_number $topMargin;
				$trialAndSiteData = $text;
				$init++;
				# say "trialAndSiteData : $trialAndSiteData";
			} else {
				# say "text : $text";
				if ($trialAndSiteData) {
					my $uSubjectId = "$trialAndSiteData $text";
					$uSubjectId =~ s/\^//;
					unless (length $uSubjectId == 22) {
						$uSubjectId =~ s/†//;
						unless (length $uSubjectId == 22) {
							($uSubjectId) = split ' \(', $uSubjectId;
							# say "uSubjectId : [$uSubjectId]";
							die "uSubjectId : [$uSubjectId]" unless (length $uSubjectId == 22);
						}
					}
					# die;
					$entryNum++;
					$patientsIds{$topMargin}->{'entryNum'}               = $entryNum;
					$patientsIds{$topMargin}->{'uSubjectId'}          = $uSubjectId;
					$patientsIds{$topMargin}->{'uSubjectIdTopMargin'} = $topMargin;
					# say "$entryNum | $uSubjectId";
					$trialAndSiteData = undef;
					$topMargin = undef;
				}
			}
		}
	}
	# p%patientsIds;
	unless ($init == keys %patientsIds) {
		p%patientsIds;
		die "$init != " . keys %patientsIds;
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
		# say "$dNum | $text";
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
				# say "$dNum | $word";
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
				$casesDates{$topMargin}->{$entryNum}->{'casesDate'}          = $casesDate;
				$casesDates{$topMargin}->{$entryNum}->{'casesYear'}          = $casesYear;
				$casesDates{$topMargin}->{$entryNum}->{'casesMonth'}         = $casesMonth;
				$casesDates{$topMargin}->{$entryNum}->{'casesWeekNumber'}    = $casesWeekNumber;
				# say "date : $dNum | $casesDate | topMargin : $topMargin";
			} elsif ($word =~ /Pos/ || $word =~ /Neg/) {
				my $style = $div->attr_get_i('style');
				my ($topMargin) = $style =~ /top:(.*)px;/;
				die unless looks_like_number $topMargin;
				$entryNum++;
				$casesDates{$topMargin}->{$entryNum}->{'swabResult'}         = $word;
				# say "$topMargin | $word";
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

sub parse_swabs {
	my ($pageTotalPatients, @divs) = @_;
	my %firstSwabs = ();
	my ($dNum, $entryNum) = (0, 0);

	# The date has two possible formats ; date alone, or age group & date collated.
	for my $div (@divs) {
		my $text = $div->as_trimmed_text;
		last if $text =~ /Abbreviations:/;
		$dNum++;
		my @words = split ' ', $text;
		for my $word (@words) {
			if ($word =~ /(...)\/(...)\/(...)/) {
				my ($visit1Diagnose, $visit2Diagnose, $visit3Diagnose) = $word =~ /(...)\/(...)\/(...)/;
				$entryNum++;
				# say "$visit1Diagnose, $visit2Diagnose, $visit3Diagnose";
				my $style = $div->attr_get_i('style');
				my ($topMargin) = $style =~ /top:(.*)px;/;
				die unless looks_like_number $topMargin;
				$firstSwabs{$topMargin}->{'visit1Diagnose'} = $visit1Diagnose;
				$firstSwabs{$topMargin}->{'visit2Diagnose'} = $visit2Diagnose;
				$firstSwabs{$topMargin}->{'visit3Diagnose'} = $visit3Diagnose;
			}
			# say "word : [$word]";
		}
	}
	return %firstSwabs;
}