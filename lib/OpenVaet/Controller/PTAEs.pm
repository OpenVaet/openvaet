package OpenVaet::Controller::PTAEs;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Data::Printer;
use FindBin;
use File::Path qw(make_path);
use lib "$FindBin::Bin/../lib";
use session;
use time;

my @adslColumns = qw(
  usubjid
  age
  agetr01
  agegr1
  agegr1n
  race
  racen
  ethnic
  ethnicn
  arace
  aracen
  racegr1
  racegr1n
  sex
  sexn
  country
  saffl
  actarm
  actarmcd
  trtsdt
  vax101dt
  vax102dt
  vax201dt
  vax202dt
  vax10udt
  vax20udt
  reactofl
  phase
  phasen
  unblnddt
  bmicat
  bmicatn
  combodfl
  covblst
  hivfl
  x1csrdt
  saf1fl
  saf2fl
  aeRows
  aeserRows
  aeser
  aestdtc
  aestdy
  aescong
  aesdisab
  aesdth
  aeshosp
  aeslife
  aesmie
  aemeres
  aerel
  aereln
  astdt
  astdtf
);

sub pfizer_trial_after_effects {
    my $self = shift;
    my $currentLanguage = $self->param('currentLanguage') // 'en';

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    $self->render(
        currentLanguage => $currentLanguage,
        languages => \%languages
    );
}

sub filter_data {
	my $self = shift;
	my $currentLanguage = $self->param('currentLanguage') // 'en';
	my $subjectsWithoutSAEs = $self->param('subjectsWithoutSAEs') // die;
	my $phase1IncludeBNT = $self->param('phase1IncludeBNT') // die;
	my $phase1IncludePlacebo = $self->param('phase1IncludePlacebo') // die;
	my $below16Include = $self->param('below16Include') // die;
	my $seniorsIncluded = $self->param('seniorsIncluded') // die;
	my $duplicatesInclude = $self->param('duplicatesInclude') // die;
	my $noCRFInclude = $self->param('noCRFInclude') // die;
	my $hivSubjectsIncluded = $self->param('hivSubjectsIncluded') // die;
	my $lackOfPIMonitoringInclude = $self->param('lackOfPIMonitoringInclude') // die;
	my $noSafetyPopFlagInclude = $self->param('noSafetyPopFlagInclude') // die;
	my $femaleIncluded = $self->param('femaleIncluded') // die;
	my $maleIncluded = $self->param('maleIncluded') // die;
	my $subjectToUnblinding = $self->param('subjectToUnblinding') // die;
	my $cutoffDate = $self->param('cutoffDate') // die;
	my $subjectsWithPriorInfect = $self->param('subjectsWithPriorInfect') // die;
	my $subjectsWithoutPriorInfect = $self->param('subjectsWithoutPriorInfect') // die;
	my $csvSeparator = $self->param('csvSeparator') // die;
	my $aeWithoutDate = $self->param('aeWithoutDate') // die;
	# Printing filtering statistics (required for the Filtering Logs).
	my @params = (
		$phase1IncludeBNT,
		$phase1IncludePlacebo,
		$below16Include,
		$seniorsIncluded,
		$duplicatesInclude,
		$noCRFInclude,
		$hivSubjectsIncluded,
		$lackOfPIMonitoringInclude,
		$noSafetyPopFlagInclude,
		$femaleIncluded,
		$maleIncluded,
		$subjectToUnblinding,
		$subjectsWithPriorInfect,
		$subjectsWithoutPriorInfect,
		$aeWithoutDate,
		$subjectsWithoutSAEs
	);
	my @paramsLabels = (
		'phase1IncludeBNT',
		'phase1IncludePlacebo',
		'below16Include',
		'seniorsIncluded',
		'duplicatesInclude',
		'noCRFInclude',
		'hivSubjectsIncluded',
		'lackOfPIMonitoringInclude',
		'noSafetyPopFlagInclude',
		'femaleIncluded',
		'maleIncluded',
		'subjectToUnblinding',
		'subjectsWithPriorInfect',
		'subjectsWithoutPriorInfect',
		'aeWithoutDate',
		'subjectsWithoutSAEs'
	);
	my $pNum = 0;
	my %params = ();
	my $path;
	for my $param (@params) {
		die unless $param eq 'true' || $param eq 'false';
		my $p = 'Y';
		$p = 'N' if $param eq 'false';
		$path .= "_$p" if $path;
		$path = "$p" if !$path;
		my $label = $paramsLabels[$pNum] // die;
		$params{$label} = $param;
		$pNum++;
	}
	$params{'cutoffDate'} = $cutoffDate;
	$params{'csvSeparator'} = $csvSeparator;
	$path .= "_$cutoffDate";
	make_path("public/pt_aes/$path") unless (-d "public/pt_aes/$path");
	open my $out1, '>:utf8', "public/pt_aes/$path/parameters.json" or die $!;
	print $out1 encode_json\%params;
	close $out1;

	my $cutoffCompdate;
	if ($cutoffDate eq 'bla') {
		$cutoffCompdate = '20210313';
	} elsif ($cutoffDate eq 'end') {
		$cutoffCompdate = '20211231';
	} else {
		die;
	}

	# Configuring duplicates & patients without CRFs required.
	my %allDuplicates = ();
	my %duplicates = ();
	my %noCRFVaxData = ();
	$allDuplicates{'10561101'}  = 11331382;
	$allDuplicates{'11331382'}  = 10561101;
	$allDuplicates{'11101123'}  = 11331405;
	$allDuplicates{'11331405'}  = 11101123;
	$allDuplicates{'11491117'}  = 12691090;
	$allDuplicates{'12691090'}  = 11491117;
	$allDuplicates{'12691070'}  = 11351357;
	$allDuplicates{'11351357'}  = 12691070;
	$allDuplicates{'11341006'}  = 10891112;
	$allDuplicates{'10891112'}  = 11341006;
	$allDuplicates{'11231105'}  = 10711213;
	$allDuplicates{'10711213'}  = 11231105;
	$duplicates{'10561101'}  = 11331382;
	# $duplicates{'11331382'}  = 10561101;
	$duplicates{'11101123'}  = 11331405;
	# $duplicates{'11331405'}  = 11101123;
	$duplicates{'11491117'}  = 12691090;
	# $duplicates{'12691090'}  = 11491117;
	$duplicates{'12691070'}  = 11351357;
	# $duplicates{'11351357'}  = 12691070;
	$duplicates{'11341006'}  = 10891112;
	# $duplicates{'10891112'}  = 11341006;
	$duplicates{'11231105'}  = 10711213;
	# $duplicates{'10711213'}  = 11231105;
	$noCRFVaxData{'11631006'}   = 1;
	$noCRFVaxData{'11631005'}   = 1;
	$noCRFVaxData{'11631008'}   = 1;
	# say "path : [$path]";
	# say "phase1IncludeBNT : $phase1IncludeBNT";
	# say "phase1IncludePlacebo : $phase1IncludePlacebo";
	# say "below16Include : $below16Include";
	# say "seniorsIncluded : $seniorsIncluded";
	# say "duplicatesInclude : $duplicatesInclude";
	# say "noCRFInclude : $noCRFInclude";
	# say "hivSubjectsIncluded : $hivSubjectsIncluded";
	# say "lackOfPIMonitoringInclude : $lackOfPIMonitoringInclude";
	# say "noSafetyPopFlagInclude : $noSafetyPopFlagInclude";
	# say "femaleIncluded : $femaleIncluded";
	# say "maleIncluded : $maleIncluded";
	# say "subjectToUnblinding : $subjectToUnblinding";
	# say "cutoffDate : $cutoffDate";
	# say "subjectsWithPriorInfect : $subjectsWithPriorInfect";
	# say "subjectsWithoutPriorInfect : $subjectsWithoutPriorInfect";
	# say "csvSeparator : $csvSeparator";

	# Loading subjects targeted.
	open my $in, '<:utf8', 'adverse_effects_raw_data.json';
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);

	# Define ADAE columns to integrate for first AE compatible.
	my @adaeColumns = qw(
	  aeser
	  aestdtc
	  aestdy
	  aescong
	  aesdisab
	  aesdth
	  aeshosp
	  aeslife
	  aesmie
	  aemeres
	  aerel
	  aereln
	  astdt
	  astdtf
	);

	# Parsing JSON input.
	my %json = %$json;
	my $filteringLogs = '';
	$filteringLogs .= "\n";
	my %filteringStats = ();
	my %filteredSubjects = ();
	open my $out5, '>:utf8', "public/pt_aes/$path/filtered_subjects_lin_reg.csv" or die $!;
	for my $adslColumn (@adslColumns) {
		print $out5 "$adslColumn$csvSeparator";
	}
	say $out5 '';
	for my $subjectId (sort{$a <=> $b} keys %json) {
		$filteringStats{'totalSubjectsOverall'}++;

		# Preliminary filterings (excluding actarmcd = Screen failures & Not assigned)
		my $actarmcd = $json{$subjectId}->{'actarmcd'} // die;
		if ($actarmcd eq 'SCRNFAIL') {
			$filteringStats{'totalScreenFailures'}++;
			$filteringStats{'screenFailures'}->{$subjectId} = 1;
			next;
		}
		if ($actarmcd eq 'NOTASSGN') {
			$filteringStats{'totalNotAssigned'}++;
			$filteringStats{'notAssigned'}->{$subjectId} = 1;
			next;
		}

		my $categoArm = $actarmcd;
		if ($actarmcd ne 'PLACEBO') {
			$categoArm = 'BNT162b2 30 mcg';
		} else {
			$categoArm = 'Placebo';
		}
		$filteringStats{'totalSubjectsPreFilters'}->{'total'}++;
		$filteringStats{'totalSubjectsPreFilters'}->{'byArms'}->{$categoArm}++;

		# Filtering phase 1 subjects.
		if ($phase1IncludeBNT ne 'true') {
			my $phase = $json{$subjectId}->{'phase'} // die;
			unless ($phase eq 'Phase 3' || $phase eq 'Phase 3_ds6000'  || $phase eq 'Phase 2_ds360/ds6000') {
				unless ($json{$subjectId}->{'adva.actarm'}) {
					die;
				}
				my $actArm = $json{$subjectId}->{'adva.actarm'} // die;
				if ($actArm ne 'Placebo') {
					$filteringStats{'totalPhase1BNT'}++;
					$filteringStats{'phase1BNT'}->{$subjectId} = 1;
					next;
				}
			}
		} else {
			my $phase = $json{$subjectId}->{'phase'} // die;
			unless ($phase eq 'Phase 3' || $phase eq 'Phase 3_ds6000'  || $phase eq 'Phase 2_ds360/ds6000') {
				unless ($json{$subjectId}->{'adva.actarm'}) {
					die;
				}
				my $actArm = $json{$subjectId}->{'adva.actarm'} // die;
				if ($actArm ne 'Placebo' && $actArm ne 'BNT162b2 Phase 1 (30 mcg)') {
					$filteringStats{'totalPhase1BNTNotB2_30mcg'}++;
					$filteringStats{'phase1BNTNotB2_30mcg'}->{$subjectId} = 1;
					next;
				}
			}
		}

		# Filtering phase 1 placebo.
		if ($phase1IncludePlacebo ne 'true') {
			my $phase = $json{$subjectId}->{'phase'} // die;
			unless ($phase eq 'Phase 3' || $phase eq 'Phase 3_ds6000'  || $phase eq 'Phase 2_ds360/ds6000') {
				unless ($json{$subjectId}->{'adva.actarm'}) {
					die;
				}
				my $actArm = $json{$subjectId}->{'adva.actarm'} // die;
				if ($actArm ne 'BNT162b2 Phase 1 (30 mcg)') {
					$filteringStats{'totalPhase1Placebo'}++;
					$filteringStats{'phase1Placebo'}->{$subjectId} = 1;
					next;
				}
			}
		}

		# Filtering below 16.
		if ($below16Include ne 'true') {
			my $age = $json{$subjectId}->{'age'} // die;
			if ($age < 16) {
				$filteringStats{'totalBelow16'}++;
				$filteringStats{'below16'}->{$subjectId} = 1;
				next;
			}
		}

		# Filtering above 54.
		if ($seniorsIncluded ne 'true') {
			my $age = $json{$subjectId}->{'age'} // die;
			if ($age > 54) {
				$filteringStats{'totalAbove54'}++;
				$filteringStats{'above54'}->{$subjectId} = 1;
				next;
			}
		}

		# Filtering duplicates.
		if ($duplicatesInclude eq 'true') {
			if (exists $duplicates{$subjectId}) {
				$filteringStats{'totalDuplicates'}++;
				$filteringStats{'duplicates'}->{$subjectId} = 1;
				next;
			}
		} else {
			if (exists $allDuplicates{$subjectId}) {
				$filteringStats{'totalDuplicates'}++;
				$filteringStats{'duplicates'}->{$subjectId} = 1;
				next;
			}
		}

		# Filtering CRF Vax Data.
		if ($noCRFInclude ne 'true') {
			if (exists $noCRFVaxData{$subjectId}) {
				$filteringStats{'totalNoCRFVaxData'}++;
				$filteringStats{'noCRFVaxData'}->{$subjectId} = 1;
				next;
			}
		}

		# Filtering HIV
		if ($hivSubjectsIncluded ne 'true') {
			my $hivfl = $json{$subjectId}->{'hivfl'} // die;
			if ($hivfl ne 'N') {
				$filteringStats{'totalHIVFlags'}++;
				$filteringStats{'hivFlags'}->{$subjectId} = 1;
				next;
			}
		}

		# Filtering Female.
		if ($femaleIncluded ne 'true') {
			my $sex = $json{$subjectId}->{'sex'} // die;
			if ($sex eq 'F') {
				$filteringStats{'totalFemales'}++;
				$filteringStats{'females'}->{$subjectId} = 1;
				next;
			}
		}

		# Filtering Male.
		if ($maleIncluded ne 'true') {
			my $sex = $json{$subjectId}->{'sex'} // die;
			if ($sex eq 'M') {
				$filteringStats{'totalMales'}++;
				$filteringStats{'males'}->{$subjectId} = 1;
				next;
			}
		}

		# Lack of PI oversight (YES-POP1 & YES-POP5)
		if ($lackOfPIMonitoringInclude ne 'true') {
			my $excludedLackOfPIOversight = 0;
			my $excludedLackOfPIOverightDate = 99999999;
			for my $dvspid (sort keys %{$json{$subjectId}->{'deviations'}}) {
				my $cape = $json{$subjectId}->{'deviations'}->{$dvspid}->{'cape'} // die;
				my @excls = split ',', $cape;
				my $pop1 = 0;
				my $pop5 = 0;
				for my $excl (@excls) {
					if ($excl eq 'YES-POP1') {
						$pop1 = 1;
					}
					if ($excl eq 'YES-POP5') {
						$pop5 = 1;
					}
				}
				if ($pop1 && $pop5) {
					my $date = $json{$subjectId}->{'deviations'}->{$dvspid}->{'dvstdtc'} // die;
					$date =~ s/\D//g;
					if ($date <= $cutoffCompdate) {
						$excludedLackOfPIOversight    = 1;
						$excludedLackOfPIOverightDate = $date if $date < $excludedLackOfPIOverightDate;
					}
				}
			}
			if ($excludedLackOfPIOversight) {
				$filteringStats{'totalLackOfPIOverSight'}++;
				$filteringStats{'lackOfPIOverSight'}->{$subjectId} = 1;
				next;
			}
		}

		# Filtering Safety Flag.
		if ($noSafetyPopFlagInclude ne 'true') {
			my $saffl = $json{$subjectId}->{'saffl'} // die;
			if ($saffl eq 'N') {
				$filteringStats{'totalExcludedFromSafety'}++;
				$filteringStats{'excludedFromSafety'}->{$subjectId} = 1;
				next;
			}
		}

		# Covid prior baseline.
		if ($subjectsWithPriorInfect ne 'true') {
			my $covblst = $json{$subjectId}->{'covblst'} // die;
			if ($covblst ne 'NEG') {
				$filteringStats{'totalWithPriorInfection'}++;
				$filteringStats{'withPriorInfection'}->{$subjectId} = 1;
				next;
			}
		}

		# No covid prior baseline.
		if ($subjectsWithoutPriorInfect ne 'true') {
			my $covblst = $json{$subjectId}->{'covblst'} // die;
			if ($covblst ne 'POS') {
				$filteringStats{'totalWithoutPriorInfection'}++;
				$filteringStats{'withoutPriorInfection'}->{$subjectId} = 1;
				next;
			}
		}

		# Creating object, flushing deviations & default AES.
		$filteredSubjects{$subjectId} = \%{$json{$subjectId}};
		delete $filteredSubjects{$subjectId}->{'deviations'};

		# If the subject made it so far, integrating its data to the end data (stats, lin reg data).
		# Calculating total serious AE to cut-off or unblinding, depending on the constrain.
		my $aeserRows = 0;
		my $aeRows    = 0;
		my $unblindingDatetime = $json{$subjectId}->{'unblnddt'} // die;
		my ($unblindingDate);
		if ($unblindingDatetime) {
			($unblindingDate) = split ' ', $unblindingDatetime;
			$unblindingDate =~ s/\D//g;
		}
		my %saesByDates = ();
		if (exists $json{$subjectId}->{'adaeRows'}) {
			for my $adaeRNum (sort{$a <=> $b} keys %{$json{$subjectId}->{'adaeRows'}}) {
				my $aeser = $json{$subjectId}->{'adaeRows'}->{$adaeRNum}->{'aeser'} // die;
				my $astdt = $json{$subjectId}->{'adaeRows'}->{$adaeRNum}->{'astdt'} // die;
				if ($aeWithoutDate ne 'true' && !$astdt) {
					$filteringStats{'totalAEsWithoutDate'}++;
					$filteringStats{'aesWithoutDate'}->{$subjectId}++;
					if ($aeser && $aeser eq 'Y') {
						$filteringStats{'totalSAEsWithoutDate'}++;
						$filteringStats{'saesWithoutDate'}->{$subjectId}++;
					}
					next;
				}
				my ($dt);
				if ($astdt) {
					($dt) = split ' ', $astdt;
					$dt   =~ s/\D//g;
					die unless $dt =~ /^........$/;
					if ($dt > $cutoffCompdate) {
						$filteringStats{'totalAEsPostCutOff'}++;
						$filteringStats{'aesPostCutOff'}->{$subjectId}++;
						if ($aeser && $aeser eq 'Y') {
							$filteringStats{'totalSAEsPostCutOff'}++;
							$filteringStats{'saesPostCutOff'}->{$subjectId}++;
						}
						next;
					}
					if ($subjectToUnblinding eq 'true') {
						if ($unblindingDate && $dt > $unblindingDate) {
							$filteringStats{'totalAEsPostUnblind'}++;
							$filteringStats{'aesPostUnblind'}->{$subjectId}++;
							if ($aeser && $aeser eq 'Y') {
								$filteringStats{'totalSAEsPostUnblind'}++;
								$filteringStats{'saesPostUnblind'}->{$subjectId}++;
							}
							next;
						}
					}
				}

				# Incrementing AE & stats for sorting by earliest known date (or default to NA if only that)
				if ($aeser && $aeser eq 'Y') {
					$aeserRows++;
					$dt = '99999999' unless $dt;
					$saesByDates{$dt}->{$adaeRNum} = \%{$json{$subjectId}->{'adaeRows'}->{$adaeRNum}};
				}
				$aeRows++;
			}
			delete $filteredSubjects{$subjectId}->{'adaeRows'};
		}

		# Incrementing post AE parsing stats.
		$filteredSubjects{$subjectId}->{'aeRows'} = $aeRows;
		$filteredSubjects{$subjectId}->{'aeserRows'} = $aeserRows;
		if ($aeserRows) {
			die unless keys %saesByDates;
			for my $dt (sort{$a <=> $b} keys %saesByDates) {
				for my $adaeRNum (sort{$a <=> $b} keys %{$saesByDates{$dt}}) {
					for my $adaeColumn (@adaeColumns) {
						my $value = $saesByDates{$dt}->{$adaeRNum}->{$adaeColumn} // die "adaeColumn : $adaeColumn";
						if (
							!exists $filteredSubjects{$subjectId}->{$adaeColumn} ||
							(
								exists $filteredSubjects{$subjectId}->{$adaeColumn} &&
								$filteredSubjects{$subjectId}->{$adaeColumn} ne 'Y' && $value eq 'Y'
							)
						) {
							$filteredSubjects{$subjectId}->{$adaeColumn} = $value;
						}
					}
				}
				last;
			}
		} else {
			if ($subjectsWithoutSAEs ne "true") {
				delete $filteredSubjects{$subjectId};
				$filteringStats{'totalWithoutSAEs'}++;
				$filteringStats{'withoutSAEs'}->{$subjectId} = 1;
				next;
			}
		}

		$filteringStats{'totalSubjectsPostFilter'}->{'total'}++;
		$filteringStats{'totalSubjectsPostFilter'}->{'byArms'}->{$categoArm}++;

		# printing .CSV row.
		for my $adslColumn (@adslColumns) {
			my $value = $filteredSubjects{$subjectId}->{$adslColumn} // '';
			print $out5 "$value$csvSeparator";
		}
		say $out5 '';
	}
	close $out5;

	# Formatting filtering details.
	open my $out2, '>:utf8', "public/pt_aes/$path/filtering_details.txt";
	say $out2 "phase1IncludeBNT : $phase1IncludeBNT";
	say $out2 "phase1IncludePlacebo : $phase1IncludePlacebo";
	say $out2 "below16Include : $below16Include";
	say $out2 "seniorsIncluded : $seniorsIncluded";
	say $out2 "duplicatesInclude : $duplicatesInclude";
	say $out2 "noCRFInclude : $noCRFInclude";
	say $out2 "hivSubjectsIncluded : $hivSubjectsIncluded";
	say $out2 "lackOfPIMonitoringInclude : $lackOfPIMonitoringInclude";
	say $out2 "noSafetyPopFlagInclude : $noSafetyPopFlagInclude";
	say $out2 "femaleIncluded : $femaleIncluded";
	say $out2 "maleIncluded : $maleIncluded";
	say $out2 "subjectToUnblinding : $subjectToUnblinding";
	say $out2 "cutoffDate : $cutoffDate";
	say $out2 "subjectsWithPriorInfect : $subjectsWithPriorInfect";
	say $out2 "subjectsWithoutPriorInfect : $subjectsWithoutPriorInfect";
	say $out2 "subjectsWithoutSAEs : $subjectsWithoutSAEs";
	say $out2 "aeWithoutDate : $aeWithoutDate";
	say $out2 "csvSeparator : $csvSeparator";
	my $totalScreenFailures = $filteringStats{'totalScreenFailures'} // die;
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	say $out2 "Preliminary filters : [Screen Failures] ($totalScreenFailures)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'screenFailures'}}) {
		say $out2 $subjectId;
	}
	my $totalNotAssigned = $filteringStats{'totalNotAssigned'} // die;
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	say $out2 "Preliminary filters : [Not Randomized] ($totalNotAssigned)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'notAssigned'}}) {
		say $out2 $subjectId;
	}
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	my $totalPhase1BNT = $filteringStats{'totalPhase1BNT'} // $filteringStats{'totalPhase1BNTNotB2_30mcg'} // 0;
	say $out2 "Include phase 1 BNT162b2 30 mcg : [$phase1IncludeBNT] ($totalPhase1BNT)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'phase1BNTNotB2_30mcg'}}) {
		say $out2 $subjectId;
	}
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'phase1BNT'}}) {
		say $out2 $subjectId;
	}
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	my $totalPhase1Placebo = $filteringStats{'totalPhase1Placebo'} // 0;
	say $out2 "Include phase 1 Placebo : [$phase1IncludePlacebo] ($totalPhase1Placebo)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'phase1Placebo'}}) {
		say $out2 $subjectId;
	}
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	my $totalBelow16 = $filteringStats{'totalBelow16'} // 0;
	say $out2 "Include subjects below 16 : [$below16Include] ($totalBelow16)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'below16'}}) {
		say $out2 $subjectId;
	}
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	my $totalAbove54 = $filteringStats{'totalAbove54'} // 0;
	say $out2 "Include subjects below 16 : [$seniorsIncluded] ($totalAbove54)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'above54'}}) {
		say $out2 $subjectId;
	}
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	my $totalDuplicates = $filteringStats{'totalDuplicates'} // 0;
	say $out2 "Include duplicates : [$duplicatesInclude] ($totalDuplicates)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'duplicates'}}) {
		say $out2 $subjectId;
	}
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	my $totalNoCRFVaxData = $filteringStats{'totalNoCRFVaxData'} // 0;
	say $out2 "Include subjects without CRF Vax Data : [$noCRFInclude] ($totalNoCRFVaxData)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'noCRFVaxData'}}) {
		say $out2 $subjectId;
	}
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	my $totalHIVFlags = $filteringStats{'totalHIVFlags'} // 0;
	say $out2 "Include subjects with HIV : [$hivSubjectsIncluded] ($totalHIVFlags)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'hivFlags'}}) {
		say $out2 $subjectId;
	}
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	my $totalFemales = $filteringStats{'totalFemales'} // 0;
	say $out2 "Include female subjects : [$femaleIncluded] ($totalFemales)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'females'}}) {
		say $out2 $subjectId;
	}
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	my $totalMales = $filteringStats{'totalMales'} // 0;
	say $out2 "Include male subjects : [$maleIncluded] ($totalMales)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'males'}}) {
		say $out2 $subjectId;
	}
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	my $totalLackOfPIOverSight = $filteringStats{'totalLackOfPIOverSight'} // 0;
	say $out2 "Include subjects with lack of oversight : [$lackOfPIMonitoringInclude] ($totalLackOfPIOverSight)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'lackOfPIOverSight'}}) {
		say $out2 $subjectId;
	}
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	my $totalExcludedFromSafety = $filteringStats{'totalExcludedFromSafety'} // 0;
	say $out2 "Include subjects without Safety Population flag : [$noSafetyPopFlagInclude] ($totalExcludedFromSafety)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'excludedFromSafety'}}) {
		say $out2 $subjectId;
	}
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	my $totalWithPriorInfection = $filteringStats{'totalWithPriorInfection'} // 0;
	say $out2 "Include subjects with prior infection: [$subjectsWithPriorInfect] ($totalWithPriorInfection)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'withPriorInfection'}}) {
		say $out2 $subjectId;
	}
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	my $totalWithoutPriorInfection = $filteringStats{'totalWithoutPriorInfection'} // 0;
	say $out2 "Include subjects without prior infection: [$subjectsWithoutPriorInfect] ($totalWithoutPriorInfection)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'withoutPriorInfection'}}) {
		say $out2 $subjectId;
	}
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	close $out2;

	# Debug.
	delete $filteringStats{'screenFailures'};
	delete $filteringStats{'notAssigned'};
	delete $filteringStats{'phase1BNTNotB2_30mcg'};
	delete $filteringStats{'phase1BNT'};
	delete $filteringStats{'phase1Placebo'};
	delete $filteringStats{'below16'};
	delete $filteringStats{'above54'};
	delete $filteringStats{'duplicates'};
	delete $filteringStats{'noCRFVaxData'};
	delete $filteringStats{'hivFlags'};
	delete $filteringStats{'lackOfPIOverSight'};
	delete $filteringStats{'females'};
	delete $filteringStats{'males'};
	delete $filteringStats{'excludedFromSafety'};
	delete $filteringStats{'withoutPriorInfection'};
	delete $filteringStats{'withPriorInfection'};
	delete $filteringStats{'aesWithoutDate'};
	delete $filteringStats{'saesWithoutDate'};
	delete $filteringStats{'aesPostCutOff'};
	delete $filteringStats{'saesPostCutOff'};
	delete $filteringStats{'aesPostUnblind'};
	delete $filteringStats{'saesPostUnblind'};
	delete $filteringStats{'withoutSAEs'};
	open my $out3, '>:utf8', "public/pt_aes/$path/filtering_abstract.json" or die $!;
	print $out3 encode_json\%filteringStats;
	close $out3;
	# p%filteringStats;
	open my $out4, '>:utf8', "public/pt_aes/$path/filtered_subjects_lin_reg.json" or die $!;
	print $out4 encode_json\%filteredSubjects;
	close $out4;

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

	$self->render(
		path => $path,
	    phase1IncludeBNT => $phase1IncludeBNT,
	    phase1IncludePlacebo => $phase1IncludePlacebo,
	    below16Include => $below16Include,
	    seniorsIncluded => $seniorsIncluded,
	    duplicatesInclude => $duplicatesInclude,
	    subjectsWithoutSAEs => $subjectsWithoutSAEs,
	    noCRFInclude => $noCRFInclude,
	    hivSubjectsIncluded => $hivSubjectsIncluded,
	    lackOfPIMonitoringInclude => $lackOfPIMonitoringInclude,
	    noSafetyPopFlagInclude => $noSafetyPopFlagInclude,
	    femaleIncluded => $femaleIncluded,
	    maleIncluded => $maleIncluded,
	    subjectToUnblinding => $subjectToUnblinding,
	    cutoffDate => $cutoffDate,
	    subjectsWithPriorInfect => $subjectsWithPriorInfect,
	    subjectsWithoutPriorInfect => $subjectsWithoutPriorInfect,
	    csvSeparator => $csvSeparator,
	    aeWithoutDate => $aeWithoutDate,
	    currentLanguage => $currentLanguage,
	    languages => \%languages
	);
}

sub render_logs {
	my $self = shift;
	my $currentLanguage = $self->param('currentLanguage') // 'en';
	my $path = $self->param('path') // die;
	my $aeWithoutDate = $self->param('aeWithoutDate') // die;
	my $phase1IncludeBNT = $self->param('phase1IncludeBNT') // die;
	my $phase1IncludePlacebo = $self->param('phase1IncludePlacebo') // die;
	my $below16Include = $self->param('below16Include') // die;
	my $seniorsIncluded = $self->param('seniorsIncluded') // die;
	my $subjectsWithoutSAEs = $self->param('subjectsWithoutSAEs') // die;
	my $duplicatesInclude = $self->param('duplicatesInclude') // die;
	my $noCRFInclude = $self->param('noCRFInclude') // die;
	my $hivSubjectsIncluded = $self->param('hivSubjectsIncluded') // die;
	my $lackOfPIMonitoringInclude = $self->param('lackOfPIMonitoringInclude') // die;
	my $noSafetyPopFlagInclude = $self->param('noSafetyPopFlagInclude') // die;
	my $femaleIncluded = $self->param('femaleIncluded') // die;
	my $maleIncluded = $self->param('maleIncluded') // die;
	my $subjectToUnblinding = $self->param('subjectToUnblinding') // die;
	my $cutoffDate = $self->param('cutoffDate') // die;
	my $subjectsWithPriorInfect = $self->param('subjectsWithPriorInfect') // die;
	my $subjectsWithoutPriorInfect = $self->param('subjectsWithoutPriorInfect') // die;
	my $csvSeparator = $self->param('csvSeparator') // die;
	say "path : [$path]";
	say "phase1IncludeBNT : $phase1IncludeBNT";
	say "phase1IncludePlacebo : $phase1IncludePlacebo";
	say "below16Include : $below16Include";
	say "seniorsIncluded : $seniorsIncluded";
	say "duplicatesInclude : $duplicatesInclude";
	say "noCRFInclude : $noCRFInclude";
	say "hivSubjectsIncluded : $hivSubjectsIncluded";
	say "lackOfPIMonitoringInclude : $lackOfPIMonitoringInclude";
	say "noSafetyPopFlagInclude : $noSafetyPopFlagInclude";
	say "femaleIncluded : $femaleIncluded";
	say "maleIncluded : $maleIncluded";
	say "subjectToUnblinding : $subjectToUnblinding";
	say "cutoffDate : $cutoffDate";
	say "subjectsWithPriorInfect : $subjectsWithPriorInfect";
	say "subjectsWithoutPriorInfect : $subjectsWithoutPriorInfect";
	say "aeWithoutDate : $aeWithoutDate";
	say "csvSeparator : $csvSeparator";

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

	# Loading filtering log abstract.
	open my $in1, '<:utf8', "public/pt_aes/$path/filtering_abstract.json";
	my $json1;
	while (<$in1>) {
		$json1 .= $_;
	}
	close $in1;
	$json1 = decode_json($json1);
	my %filteringStats = %$json1;
	# p%filteringStats;

	$self->render(
		path => $path,
	    phase1IncludeBNT => $phase1IncludeBNT,
	    phase1IncludePlacebo => $phase1IncludePlacebo,
	    below16Include => $below16Include,
	    seniorsIncluded => $seniorsIncluded,
	    duplicatesInclude => $duplicatesInclude,
	    noCRFInclude => $noCRFInclude,
	    hivSubjectsIncluded => $hivSubjectsIncluded,
	    lackOfPIMonitoringInclude => $lackOfPIMonitoringInclude,
	    noSafetyPopFlagInclude => $noSafetyPopFlagInclude,
	    subjectsWithoutSAEs => $subjectsWithoutSAEs,
	    femaleIncluded => $femaleIncluded,
	    maleIncluded => $maleIncluded,
	    subjectToUnblinding => $subjectToUnblinding,
	    aeWithoutDate => $aeWithoutDate,
	    cutoffDate => $cutoffDate,
	    subjectsWithPriorInfect => $subjectsWithPriorInfect,
	    subjectsWithoutPriorInfect => $subjectsWithoutPriorInfect,
	    csvSeparator => $csvSeparator,
	    currentLanguage => $currentLanguage,
	    languages => \%languages,
	    filteringStats => \%filteringStats
	);
}

sub render_lin_reg_data {
	my $self = shift;
	my $currentLanguage = $self->param('currentLanguage') // 'en';
	my $path = $self->param('path') // die;
	my $phase1IncludeBNT = $self->param('phase1IncludeBNT') // die;
	my $phase1IncludePlacebo = $self->param('phase1IncludePlacebo') // die;
	my $subjectsWithoutSAEs = $self->param('subjectsWithoutSAEs') // die;
	my $aeWithoutDate = $self->param('aeWithoutDate') // die;
	my $below16Include = $self->param('below16Include') // die;
	my $seniorsIncluded = $self->param('seniorsIncluded') // die;
	my $duplicatesInclude = $self->param('duplicatesInclude') // die;
	my $noCRFInclude = $self->param('noCRFInclude') // die;
	my $hivSubjectsIncluded = $self->param('hivSubjectsIncluded') // die;
	my $lackOfPIMonitoringInclude = $self->param('lackOfPIMonitoringInclude') // die;
	my $noSafetyPopFlagInclude = $self->param('noSafetyPopFlagInclude') // die;
	my $femaleIncluded = $self->param('femaleIncluded') // die;
	my $maleIncluded = $self->param('maleIncluded') // die;
	my $subjectToUnblinding = $self->param('subjectToUnblinding') // die;
	my $cutoffDate = $self->param('cutoffDate') // die;
	my $subjectsWithPriorInfect = $self->param('subjectsWithPriorInfect') // die;
	my $subjectsWithoutPriorInfect = $self->param('subjectsWithoutPriorInfect') // die;
	my $csvSeparator = $self->param('csvSeparator') // die;
	say "path : [$path]";
	say "phase1IncludeBNT : $phase1IncludeBNT";
	say "phase1IncludePlacebo : $phase1IncludePlacebo";
	say "below16Include : $below16Include";
	say "seniorsIncluded : $seniorsIncluded";
	say "duplicatesInclude : $duplicatesInclude";
	say "noCRFInclude : $noCRFInclude";
	say "hivSubjectsIncluded : $hivSubjectsIncluded";
	say "lackOfPIMonitoringInclude : $lackOfPIMonitoringInclude";
	say "noSafetyPopFlagInclude : $noSafetyPopFlagInclude";
	say "femaleIncluded : $femaleIncluded";
	say "maleIncluded : $maleIncluded";
	say "subjectToUnblinding : $subjectToUnblinding";
	say "cutoffDate : $cutoffDate";
	say "subjectsWithPriorInfect : $subjectsWithPriorInfect";
	say "subjectsWithoutPriorInfect : $subjectsWithoutPriorInfect";
	say "aeWithoutDate : $aeWithoutDate";
	say "csvSeparator : $csvSeparator";

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

	# Loading filtering log abstract.
	open my $in1, '<:utf8', "public/pt_aes/$path/filtered_subjects_lin_reg.json";
	my $json1;
	while (<$in1>) {
		$json1 .= $_;
	}
	close $in1;
	$json1 = decode_json($json1);
	my %filteredSubjects = %$json1;
	# p%filteredSubjects;

	$self->render(
		path => $path,
	    phase1IncludeBNT => $phase1IncludeBNT,
	    phase1IncludePlacebo => $phase1IncludePlacebo,
	    aeWithoutDate => $aeWithoutDate,
	    below16Include => $below16Include,
	    seniorsIncluded => $seniorsIncluded,
	    duplicatesInclude => $duplicatesInclude,
	    noCRFInclude => $noCRFInclude,
	    hivSubjectsIncluded => $hivSubjectsIncluded,
	    lackOfPIMonitoringInclude => $lackOfPIMonitoringInclude,
	    noSafetyPopFlagInclude => $noSafetyPopFlagInclude,
	    subjectsWithoutSAEs => $subjectsWithoutSAEs,
	    femaleIncluded => $femaleIncluded,
	    maleIncluded => $maleIncluded,
	    subjectToUnblinding => $subjectToUnblinding,
	    cutoffDate => $cutoffDate,
	    subjectsWithPriorInfect => $subjectsWithPriorInfect,
	    subjectsWithoutPriorInfect => $subjectsWithoutPriorInfect,
	    csvSeparator => $csvSeparator,
	    currentLanguage => $currentLanguage,
	    languages => \%languages,
	    filteredSubjects => \%filteredSubjects,
	    adslColumns => \@adslColumns
	);
}

sub render_stats {
	my $self = shift;
	my $currentLanguage = $self->param('currentLanguage') // 'en';
	my $path = $self->param('path') // die;
	my $phase1IncludeBNT = $self->param('phase1IncludeBNT') // die;
	my $aeWithoutDate = $self->param('aeWithoutDate') // die;
	my $phase1IncludePlacebo = $self->param('phase1IncludePlacebo') // die;
	my $subjectsWithoutSAEs = $self->param('subjectsWithoutSAEs') // die;
	my $below16Include = $self->param('below16Include') // die;
	my $seniorsIncluded = $self->param('seniorsIncluded') // die;
	my $duplicatesInclude = $self->param('duplicatesInclude') // die;
	my $noCRFInclude = $self->param('noCRFInclude') // die;
	my $hivSubjectsIncluded = $self->param('hivSubjectsIncluded') // die;
	my $lackOfPIMonitoringInclude = $self->param('lackOfPIMonitoringInclude') // die;
	my $noSafetyPopFlagInclude = $self->param('noSafetyPopFlagInclude') // die;
	my $femaleIncluded = $self->param('femaleIncluded') // die;
	my $maleIncluded = $self->param('maleIncluded') // die;
	my $subjectToUnblinding = $self->param('subjectToUnblinding') // die;
	my $cutoffDate = $self->param('cutoffDate') // die;
	my $subjectsWithPriorInfect = $self->param('subjectsWithPriorInfect') // die;
	my $subjectsWithoutPriorInfect = $self->param('subjectsWithoutPriorInfect') // die;
	my $csvSeparator = $self->param('csvSeparator') // die;
	say "path : [$path]";
	say "phase1IncludeBNT : $phase1IncludeBNT";
	say "phase1IncludePlacebo : $phase1IncludePlacebo";
	say "below16Include : $below16Include";
	say "seniorsIncluded : $seniorsIncluded";
	say "duplicatesInclude : $duplicatesInclude";
	say "noCRFInclude : $noCRFInclude";
	say "hivSubjectsIncluded : $hivSubjectsIncluded";
	say "lackOfPIMonitoringInclude : $lackOfPIMonitoringInclude";
	say "noSafetyPopFlagInclude : $noSafetyPopFlagInclude";
	say "femaleIncluded : $femaleIncluded";
	say "maleIncluded : $maleIncluded";
	say "subjectToUnblinding : $subjectToUnblinding";
	say "cutoffDate : $cutoffDate";
	say "subjectsWithPriorInfect : $subjectsWithPriorInfect";
	say "subjectsWithoutPriorInfect : $subjectsWithoutPriorInfect";
	say "aeWithoutDate : $aeWithoutDate";
	say "csvSeparator : $csvSeparator";

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

	# Loading filtering log abstract.
	open my $in1, '<:utf8', "public/pt_aes/$path/filtering_abstract.json";
	my $json1;
	while (<$in1>) {
		$json1 .= $_;
	}
	close $in1;
	$json1 = decode_json($json1);
	my %filteringStats = %$json1;
	p%filteringStats;

	$self->render(
		path => $path,
	    phase1IncludeBNT => $phase1IncludeBNT,
	    phase1IncludePlacebo => $phase1IncludePlacebo,
	    aeWithoutDate => $aeWithoutDate,
	    below16Include => $below16Include,
	    seniorsIncluded => $seniorsIncluded,
	    duplicatesInclude => $duplicatesInclude,
	    noCRFInclude => $noCRFInclude,
	    hivSubjectsIncluded => $hivSubjectsIncluded,
	    lackOfPIMonitoringInclude => $lackOfPIMonitoringInclude,
	    noSafetyPopFlagInclude => $noSafetyPopFlagInclude,
	    femaleIncluded => $femaleIncluded,
	    subjectsWithoutSAEs => $subjectsWithoutSAEs,
	    maleIncluded => $maleIncluded,
	    subjectToUnblinding => $subjectToUnblinding,
	    cutoffDate => $cutoffDate,
	    subjectsWithPriorInfect => $subjectsWithPriorInfect,
	    subjectsWithoutPriorInfect => $subjectsWithoutPriorInfect,
	    csvSeparator => $csvSeparator,
	    currentLanguage => $currentLanguage,
	    languages => \%languages,
	    filteringStats => \%filteringStats
	);
}

1;