package OpenVaet::Controller::DataCompletion;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Data::Printer;
use FindBin;
use lib "$FindBin::Bin/../lib";
use session;
use time;
use country;

my $softwareName = 'OpenVAET';
my $completionStatsFile = 'stats/completion_stats.json';
my $treatmentLimit = 1000;

sub by_countries_and_states {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'fr';

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    # Wizards
	my %wizards = ();
	$wizards{'patientAgesConfirmations'} = 'Patient Ages Confirmations';
	$wizards{'pregnanciesConfirmations'} = 'Pregnancies Confirmations';
	$wizards{'pregnanciesSeriousnessConfirmations'} = 'Pregnancies Seriousness Confirmations';
	$wizards{'breastMilkExposuresConfirmations'} = 'Breast Milk Exposures Confirmations';
	$wizards{'breastMilkExposuresPostTreatments'} = 'Exposure via Breast-Milk Post Treatments';

    # Fetching latest update ; generating stats if required.
    my $sTb = $self->dbh->selectrow_hashref("SELECT latestCountriesStatsUpdateTimestamp FROM software WHERE name = ?", undef, $softwareName);
    die unless keys %$sTb;
    my $latestCountriesStatsUpdateTimestamp = %$sTb{'latestCountriesStatsUpdateTimestamp'};
    my $currentTimestamp = time::current_timestamp();
    if (!$latestCountriesStatsUpdateTimestamp || (($latestCountriesStatsUpdateTimestamp + 1800) < $currentTimestamp)) {
    	update_stats($self, $currentTimestamp);
    	say "Stats update required";
    }

    $self->render(
        currentLanguage => $currentLanguage,
        languages => \%languages,
        wizards => \%wizards
    );
}

sub query_stats_refresh {
    my $self = shift;
    my $currentTimestamp = time::current_timestamp();
	update_stats($self, $currentTimestamp);
	$self->render(text => 'ok');
}

sub update_stats {
	my ($self, $currentTimestamp) = @_;
	my %statistics = ();
	my $tb = $self->dbh->selectall_hashref("
		SELECT
			report.id as reportId,
			report.countryId,
			country.name as countryName,
			report.countryStateId,
			country_state.name as countryStateName,
			patientAgeConfirmationRequired,
			patientAgeConfirmation,
			patientAgeFixed,
			pregnancyConfirmationRequired,
			pregnancyConfirmation,
			pregnancySeriousnessConfirmationRequired,
			pregnancySeriousnessConfirmation,
			breastMilkExposureConfirmationRequired,
			breastMilkExposureConfirmation,
			breastMilkExposurePostTreatmentRequired,
			breastMilkExposurePostTreatment,
			hospitalizedFixed,
			patientDiedFixed,
			permanentDisabilityFixed,
			lifeThreatningFixed
		FROM report
			LEFT JOIN country ON country.id = report.countryId
			LEFT JOIN country_state ON country_state.id = report.countryStateId
	", 'reportId');
	for my $reportId (sort{$a <=> $b} keys %$tb) {
		my $countryId = %$tb{$reportId}->{'countryId'};
		my $countryName = %$tb{$reportId}->{'countryName'} // 'Unknown Country';
		my $countryStateId = %$tb{$reportId}->{'countryStateId'};
		my $countryStateName = %$tb{$reportId}->{'countryStateName'};
		my $patientAgeConfirmationRequired = %$tb{$reportId}->{'patientAgeConfirmationRequired'} // die;
        $patientAgeConfirmationRequired         = unpack("N", pack("B32", substr("0" x 32 . $patientAgeConfirmationRequired, -32)));
		my $pregnancyConfirmationRequired = %$tb{$reportId}->{'pregnancyConfirmationRequired'} // die;
        $pregnancyConfirmationRequired          = unpack("N", pack("B32", substr("0" x 32 . $pregnancyConfirmationRequired, -32)));
		my $pregnancySeriousnessConfirmationRequired = %$tb{$reportId}->{'pregnancySeriousnessConfirmationRequired'} // die;
        $pregnancySeriousnessConfirmationRequired    = unpack("N", pack("B32", substr("0" x 32 . $pregnancySeriousnessConfirmationRequired, -32)));
		my $breastMilkExposureConfirmationRequired   = %$tb{$reportId}->{'breastMilkExposureConfirmationRequired'} // die;
        $breastMilkExposureConfirmationRequired      = unpack("N", pack("B32", substr("0" x 32 . $breastMilkExposureConfirmationRequired, -32)));
		my $breastMilkExposurePostTreatmentRequired   = %$tb{$reportId}->{'breastMilkExposurePostTreatmentRequired'} // die;
        $breastMilkExposurePostTreatmentRequired      = unpack("N", pack("B32", substr("0" x 32 . $breastMilkExposurePostTreatmentRequired, -32)));
		my $hospitalizedFixed = %$tb{$reportId}->{'hospitalizedFixed'} // die;
        $hospitalizedFixed = unpack("N", pack("B32", substr("0" x 32 . $hospitalizedFixed, -32)));
		my $patientDiedFixed = %$tb{$reportId}->{'patientDiedFixed'} // die;
        $patientDiedFixed = unpack("N", pack("B32", substr("0" x 32 . $patientDiedFixed, -32)));
		my $permanentDisabilityFixed = %$tb{$reportId}->{'permanentDisabilityFixed'} // die;
        $permanentDisabilityFixed = unpack("N", pack("B32", substr("0" x 32 . $permanentDisabilityFixed, -32)));
		my $lifeThreatningFixed = %$tb{$reportId}->{'lifeThreatningFixed'} // die;
        $lifeThreatningFixed = unpack("N", pack("B32", substr("0" x 32 . $lifeThreatningFixed, -32)));
		my $patientAgeFixed = %$tb{$reportId}->{'patientAgeFixed'};
		my $patientAgeConfirmation = %$tb{$reportId}->{'patientAgeConfirmation'};
		# Patient age confirmation.
		if ($patientAgeConfirmationRequired) {
			$statistics{'patientAgesConfirmations'}->{'total'}++;
			if ($patientDiedFixed) {
				$statistics{'patientAgesConfirmations'}->{'bySeriousness'}->{'deaths'}->{'total'}++;
			} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
				$statistics{'patientAgesConfirmations'}->{'bySeriousness'}->{'serious'}->{'total'}++;
			} else {
				$statistics{'patientAgesConfirmations'}->{'bySeriousness'}->{'nonSerious'}->{'total'}++;
			}
			$statistics{'patientAgesConfirmations'}->{'byCountries'}->{$countryName}->{'total'}++;
			if ($patientDiedFixed) {
				$statistics{'patientAgesConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'deaths'}->{'total'}++;
			} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
				$statistics{'patientAgesConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'serious'}->{'total'}++;
			} else {
				$statistics{'patientAgesConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'nonSerious'}->{'total'}++;
			}
			if ($countryName eq 'United States of America') {
				unless ($countryStateName) {
					$countryStateName = 'Unknown';
					$countryStateId = 19;
				}
				$statistics{'patientAgesConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'total'}++;
				if ($patientDiedFixed) {
					$statistics{'patientAgesConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'deaths'}->{'total'}++;
				} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
					$statistics{'patientAgesConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'serious'}->{'total'}++;
				} else {
					$statistics{'patientAgesConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'nonSerious'}->{'total'}++;
				}
			}
			my $patientAgeConfirmation = %$tb{$reportId}->{'patientAgeConfirmation'};
			if (defined $patientAgeConfirmation) {
				$statistics{'patientAgesConfirmations'}->{'reviewed'}++;
				if ($patientDiedFixed) {
					$statistics{'patientAgesConfirmations'}->{'bySeriousness'}->{'deaths'}->{'reviewed'}++;
				} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
					$statistics{'patientAgesConfirmations'}->{'bySeriousness'}->{'serious'}->{'reviewed'}++;
				} else {
					$statistics{'patientAgesConfirmations'}->{'bySeriousness'}->{'nonSerious'}->{'reviewed'}++;
				}
				$statistics{'patientAgesConfirmations'}->{'byCountries'}->{$countryName}->{'reviewed'}++;
				if ($patientDiedFixed) {
					$statistics{'patientAgesConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'deaths'}->{'reviewed'}++;
				} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
					$statistics{'patientAgesConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'serious'}->{'reviewed'}++;
				} else {
					$statistics{'patientAgesConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'nonSerious'}->{'reviewed'}++;
				}
				if ($countryName eq 'United States of America') {
					unless ($countryStateName) {
						$countryStateName = 'Unknown';
						$countryStateId = 19;
					}
					$statistics{'patientAgesConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'reviewed'}++;
					if ($patientDiedFixed) {
						$statistics{'patientAgesConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'deaths'}->{'reviewed'}++;
					} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
						$statistics{'patientAgesConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'serious'}->{'reviewed'}++;
					} else {
						$statistics{'patientAgesConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'nonSerious'}->{'reviewed'}++;
					}
				}
	        	if ($patientAgeFixed) {
					$statistics{'patientAgesConfirmations'}->{'confirmed'}++;
					if ($patientDiedFixed) {
						$statistics{'patientAgesConfirmations'}->{'bySeriousness'}->{'deaths'}->{'confirmed'}++;
					} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
						$statistics{'patientAgesConfirmations'}->{'bySeriousness'}->{'serious'}->{'confirmed'}++;
					} else {
						$statistics{'patientAgesConfirmations'}->{'bySeriousness'}->{'nonSerious'}->{'confirmed'}++;
					}
					$statistics{'patientAgesConfirmations'}->{'byCountries'}->{$countryName}->{'confirmed'}++;
					if ($patientDiedFixed) {
						$statistics{'patientAgesConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'deaths'}->{'confirmed'}++;
					} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
						$statistics{'patientAgesConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'serious'}->{'confirmed'}++;
					} else {
						$statistics{'patientAgesConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'nonSerious'}->{'confirmed'}++;
					}
					if ($countryName eq 'United States of America') {
						unless ($countryStateName) {
							$countryStateName = 'Unknown';
							$countryStateId = 19;
						}
						$statistics{'patientAgesConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'confirmed'}++;
						if ($patientDiedFixed) {
							$statistics{'patientAgesConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'deaths'}->{'confirmed'}++;
						} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
							$statistics{'patientAgesConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'serious'}->{'confirmed'}++;
						} else {
							$statistics{'patientAgesConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'nonSerious'}->{'confirmed'}++;
						}
					}
	        	}
			}
		}

		# Pregnancies confirmations.
		if ($pregnancyConfirmationRequired) {
			$statistics{'pregnanciesConfirmations'}->{'total'}++;
			if ($patientDiedFixed) {
				$statistics{'pregnanciesConfirmations'}->{'bySeriousness'}->{'deaths'}->{'total'}++;
			} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
				$statistics{'pregnanciesConfirmations'}->{'bySeriousness'}->{'serious'}->{'total'}++;
			} else {
				$statistics{'pregnanciesConfirmations'}->{'bySeriousness'}->{'nonSerious'}->{'total'}++;
			}
			$statistics{'pregnanciesConfirmations'}->{'byCountries'}->{$countryName}->{'total'}++;
			if ($patientDiedFixed) {
				$statistics{'pregnanciesConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'deaths'}->{'total'}++;
			} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
				$statistics{'pregnanciesConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'serious'}->{'total'}++;
			} else {
				$statistics{'pregnanciesConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'nonSerious'}->{'total'}++;
			}
			if ($countryName eq 'United States of America') {
				unless ($countryStateName) {
					$countryStateName = 'Unknown';
					$countryStateId = 19;
				}
				$statistics{'pregnanciesConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'total'}++;
				if ($patientDiedFixed) {
					$statistics{'pregnanciesConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'deaths'}->{'total'}++;
				} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
					$statistics{'pregnanciesConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'serious'}->{'total'}++;
				} else {
					$statistics{'pregnanciesConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'nonSerious'}->{'total'}++;
				}
			}
			my $pregnancyConfirmation = %$tb{$reportId}->{'pregnancyConfirmation'};
			if (defined $pregnancyConfirmation) {
				$statistics{'pregnanciesConfirmations'}->{'reviewed'}++;
				if ($patientDiedFixed) {
					$statistics{'pregnanciesConfirmations'}->{'bySeriousness'}->{'deaths'}->{'reviewed'}++;
				} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
					$statistics{'pregnanciesConfirmations'}->{'bySeriousness'}->{'serious'}->{'reviewed'}++;
				} else {
					$statistics{'pregnanciesConfirmations'}->{'bySeriousness'}->{'nonSerious'}->{'reviewed'}++;
				}
				$statistics{'pregnanciesConfirmations'}->{'byCountries'}->{$countryName}->{'reviewed'}++;
				if ($patientDiedFixed) {
					$statistics{'pregnanciesConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'deaths'}->{'reviewed'}++;
				} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
					$statistics{'pregnanciesConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'serious'}->{'reviewed'}++;
				} else {
					$statistics{'pregnanciesConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'nonSerious'}->{'reviewed'}++;
				}
				if ($countryName eq 'United States of America') {
					unless ($countryStateName) {
						$countryStateName = 'Unknown';
						$countryStateId = 19;
					}
					$statistics{'pregnanciesConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'reviewed'}++;
					if ($patientDiedFixed) {
						$statistics{'pregnanciesConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'deaths'}->{'reviewed'}++;
					} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
						$statistics{'pregnanciesConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'serious'}->{'reviewed'}++;
					} else {
						$statistics{'pregnanciesConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'nonSerious'}->{'reviewed'}++;
					}
				}
	        	$pregnancyConfirmation = unpack("N", pack("B32", substr("0" x 32 . $pregnancyConfirmation, -32)));
	        	if ($pregnancyConfirmation) {
					$statistics{'pregnanciesConfirmations'}->{'confirmed'}++;
					if ($patientDiedFixed) {
						$statistics{'pregnanciesConfirmations'}->{'bySeriousness'}->{'deaths'}->{'confirmed'}++;
					} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
						$statistics{'pregnanciesConfirmations'}->{'bySeriousness'}->{'serious'}->{'confirmed'}++;
					} else {
						$statistics{'pregnanciesConfirmations'}->{'bySeriousness'}->{'nonSerious'}->{'confirmed'}++;
					}
					$statistics{'pregnanciesConfirmations'}->{'byCountries'}->{$countryName}->{'confirmed'}++;
					if ($patientDiedFixed) {
						$statistics{'pregnanciesConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'deaths'}->{'confirmed'}++;
					} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
						$statistics{'pregnanciesConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'serious'}->{'confirmed'}++;
					} else {
						$statistics{'pregnanciesConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'nonSerious'}->{'confirmed'}++;
					}
					if ($countryName eq 'United States of America') {
						unless ($countryStateName) {
							$countryStateName = 'Unknown';
							$countryStateId = 19;
						}
						$statistics{'pregnanciesConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'confirmed'}++;
						if ($patientDiedFixed) {
							$statistics{'pregnanciesConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'deaths'}->{'confirmed'}++;
						} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
							$statistics{'pregnanciesConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'serious'}->{'confirmed'}++;
						} else {
							$statistics{'pregnanciesConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'nonSerious'}->{'confirmed'}++;
						}
					}
	        	}
			}
		}

		# Pregnancies seriousness confirmations.
		if ($pregnancySeriousnessConfirmationRequired) {
			$statistics{'pregnanciesSeriousnessConfirmations'}->{'total'}++;
			if ($patientDiedFixed) {
				$statistics{'pregnanciesSeriousnessConfirmations'}->{'bySeriousness'}->{'deaths'}->{'total'}++;
			} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
				$statistics{'pregnanciesSeriousnessConfirmations'}->{'bySeriousness'}->{'serious'}->{'total'}++;
			} else {
				$statistics{'pregnanciesSeriousnessConfirmations'}->{'bySeriousness'}->{'nonSerious'}->{'total'}++;
			}
			$statistics{'pregnanciesSeriousnessConfirmations'}->{'byCountries'}->{$countryName}->{'total'}++;
			if ($patientDiedFixed) {
				$statistics{'pregnanciesSeriousnessConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'deaths'}->{'total'}++;
			} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
				$statistics{'pregnanciesSeriousnessConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'serious'}->{'total'}++;
			} else {
				$statistics{'pregnanciesSeriousnessConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'nonSerious'}->{'total'}++;
			}
			if ($countryName eq 'United States of America') {
				unless ($countryStateName) {
					$countryStateName = 'Unknown';
					$countryStateId = 19;
				}
				$statistics{'pregnanciesSeriousnessConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'total'}++;
				if ($patientDiedFixed) {
					$statistics{'pregnanciesSeriousnessConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'deaths'}->{'total'}++;
				} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
					$statistics{'pregnanciesSeriousnessConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'serious'}->{'total'}++;
				} else {
					$statistics{'pregnanciesSeriousnessConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'nonSerious'}->{'total'}++;
				}
			}
			my $pregnancySeriousnessConfirmation = %$tb{$reportId}->{'pregnancySeriousnessConfirmation'};
			if (defined $pregnancySeriousnessConfirmation) {
				$statistics{'pregnanciesSeriousnessConfirmations'}->{'reviewed'}++;
				if ($patientDiedFixed) {
					$statistics{'pregnanciesSeriousnessConfirmations'}->{'bySeriousness'}->{'deaths'}->{'reviewed'}++;
				} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
					$statistics{'pregnanciesSeriousnessConfirmations'}->{'bySeriousness'}->{'serious'}->{'reviewed'}++;
				} else {
					$statistics{'pregnanciesSeriousnessConfirmations'}->{'bySeriousness'}->{'nonSerious'}->{'reviewed'}++;
				}
				$statistics{'pregnanciesSeriousnessConfirmations'}->{'byCountries'}->{$countryName}->{'reviewed'}++;
				if ($patientDiedFixed) {
					$statistics{'pregnanciesSeriousnessConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'deaths'}->{'reviewed'}++;
				} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
					$statistics{'pregnanciesSeriousnessConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'serious'}->{'reviewed'}++;
				} else {
					$statistics{'pregnanciesSeriousnessConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'nonSerious'}->{'reviewed'}++;
				}
				if ($countryName eq 'United States of America') {
					unless ($countryStateName) {
						$countryStateName = 'Unknown';
						$countryStateId = 19;
					}
					$statistics{'pregnanciesSeriousnessConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'reviewed'}++;
					if ($patientDiedFixed) {
						$statistics{'pregnanciesSeriousnessConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'deaths'}->{'reviewed'}++;
					} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
						$statistics{'pregnanciesSeriousnessConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'serious'}->{'reviewed'}++;
					} else {
						$statistics{'pregnanciesSeriousnessConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'nonSerious'}->{'reviewed'}++;
					}
				}
	        	$pregnancySeriousnessConfirmation = unpack("N", pack("B32", substr("0" x 32 . $pregnancySeriousnessConfirmation, -32)));
	        	if ($pregnancySeriousnessConfirmation) {
					$statistics{'pregnanciesSeriousnessConfirmations'}->{'confirmed'}++;
					if ($patientDiedFixed) {
						$statistics{'pregnanciesSeriousnessConfirmations'}->{'bySeriousness'}->{'deaths'}->{'confirmed'}++;
					} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
						$statistics{'pregnanciesSeriousnessConfirmations'}->{'bySeriousness'}->{'serious'}->{'confirmed'}++;
					} else {
						$statistics{'pregnanciesSeriousnessConfirmations'}->{'bySeriousness'}->{'nonSerious'}->{'confirmed'}++;
					}
					$statistics{'pregnanciesSeriousnessConfirmations'}->{'byCountries'}->{$countryName}->{'confirmed'}++;
					if ($patientDiedFixed) {
						$statistics{'pregnanciesSeriousnessConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'deaths'}->{'confirmed'}++;
					} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
						$statistics{'pregnanciesSeriousnessConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'serious'}->{'confirmed'}++;
					} else {
						$statistics{'pregnanciesSeriousnessConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'nonSerious'}->{'confirmed'}++;
					}
					if ($countryName eq 'United States of America') {
						unless ($countryStateName) {
							$countryStateName = 'Unknown';
							$countryStateId = 19;
						}
						$statistics{'pregnanciesSeriousnessConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'confirmed'}++;
						if ($patientDiedFixed) {
							$statistics{'pregnanciesSeriousnessConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'deaths'}->{'confirmed'}++;
						} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
							$statistics{'pregnanciesSeriousnessConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'serious'}->{'confirmed'}++;
						} else {
							$statistics{'pregnanciesSeriousnessConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'nonSerious'}->{'confirmed'}++;
						}
					}
	        	}
			}
		}

		# Breast milk exposures confirmation
		if ($breastMilkExposureConfirmationRequired) {
			$statistics{'breastMilkExposuresConfirmations'}->{'total'}++;
			if ($patientDiedFixed) {
				$statistics{'breastMilkExposuresConfirmations'}->{'bySeriousness'}->{'deaths'}->{'total'}++;
			} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
				$statistics{'breastMilkExposuresConfirmations'}->{'bySeriousness'}->{'serious'}->{'total'}++;
			} else {
				$statistics{'breastMilkExposuresConfirmations'}->{'bySeriousness'}->{'nonSerious'}->{'total'}++;
			}
			$statistics{'breastMilkExposuresConfirmations'}->{'byCountries'}->{$countryName}->{'total'}++;
			if ($patientDiedFixed) {
				$statistics{'breastMilkExposuresConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'deaths'}->{'total'}++;
			} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
				$statistics{'breastMilkExposuresConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'serious'}->{'total'}++;
			} else {
				$statistics{'breastMilkExposuresConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'nonSerious'}->{'total'}++;
			}
			if ($countryName eq 'United States of America') {
				unless ($countryStateName) {
					$countryStateName = 'Unknown';
					$countryStateId = 19;
				}
				$statistics{'breastMilkExposuresConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'total'}++;
				if ($patientDiedFixed) {
					$statistics{'breastMilkExposuresConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'deaths'}->{'total'}++;
				} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
					$statistics{'breastMilkExposuresConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'serious'}->{'total'}++;
				} else {
					$statistics{'breastMilkExposuresConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'nonSerious'}->{'total'}++;
				}
			}
			my $breastMilkExposureConfirmation = %$tb{$reportId}->{'breastMilkExposureConfirmation'};
			if (defined $breastMilkExposureConfirmation) {
				$statistics{'breastMilkExposuresConfirmations'}->{'reviewed'}++;
				if ($patientDiedFixed) {
					$statistics{'breastMilkExposuresConfirmations'}->{'bySeriousness'}->{'deaths'}->{'reviewed'}++;
				} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
					$statistics{'breastMilkExposuresConfirmations'}->{'bySeriousness'}->{'serious'}->{'reviewed'}++;
				} else {
					$statistics{'breastMilkExposuresConfirmations'}->{'bySeriousness'}->{'nonSerious'}->{'reviewed'}++;
				}
				$statistics{'breastMilkExposuresConfirmations'}->{'byCountries'}->{$countryName}->{'reviewed'}++;
				if ($patientDiedFixed) {
					$statistics{'breastMilkExposuresConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'deaths'}->{'reviewed'}++;
				} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
					$statistics{'breastMilkExposuresConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'serious'}->{'reviewed'}++;
				} else {
					$statistics{'breastMilkExposuresConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'nonSerious'}->{'reviewed'}++;
				}
				if ($countryName eq 'United States of America') {
					unless ($countryStateName) {
						$countryStateName = 'Unknown';
						$countryStateId = 19;
					}
					$statistics{'breastMilkExposuresConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'reviewed'}++;
					if ($patientDiedFixed) {
						$statistics{'breastMilkExposuresConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'deaths'}->{'reviewed'}++;
					} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
						$statistics{'breastMilkExposuresConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'serious'}->{'reviewed'}++;
					} else {
						$statistics{'breastMilkExposuresConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'nonSerious'}->{'reviewed'}++;
					}
				}
	        	$breastMilkExposureConfirmation = unpack("N", pack("B32", substr("0" x 32 . $breastMilkExposureConfirmation, -32)));
	        	if ($breastMilkExposureConfirmation) {
					$statistics{'breastMilkExposuresConfirmations'}->{'confirmed'}++;
					if ($patientDiedFixed) {
						$statistics{'breastMilkExposuresConfirmations'}->{'bySeriousness'}->{'deaths'}->{'confirmed'}++;
					} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
						$statistics{'breastMilkExposuresConfirmations'}->{'bySeriousness'}->{'serious'}->{'confirmed'}++;
					} else {
						$statistics{'breastMilkExposuresConfirmations'}->{'bySeriousness'}->{'nonSerious'}->{'confirmed'}++;
					}
					$statistics{'breastMilkExposuresConfirmations'}->{'byCountries'}->{$countryName}->{'confirmed'}++;
					if ($patientDiedFixed) {
						$statistics{'breastMilkExposuresConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'deaths'}->{'confirmed'}++;
					} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
						$statistics{'breastMilkExposuresConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'serious'}->{'confirmed'}++;
					} else {
						$statistics{'breastMilkExposuresConfirmations'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'nonSerious'}->{'confirmed'}++;
					}
					if ($countryName eq 'United States of America') {
						unless ($countryStateName) {
							$countryStateName = 'Unknown';
							$countryStateId = 19;
						}
						$statistics{'breastMilkExposuresConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'confirmed'}++;
						if ($patientDiedFixed) {
							$statistics{'breastMilkExposuresConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'deaths'}->{'confirmed'}++;
						} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
							$statistics{'breastMilkExposuresConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'serious'}->{'confirmed'}++;
						} else {
							$statistics{'breastMilkExposuresConfirmations'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'nonSerious'}->{'confirmed'}++;
						}
					}
	        	}
			}
		}

		# Breast milk exposures post treatments.
		if ($breastMilkExposurePostTreatmentRequired) {
			$statistics{'breastMilkExposuresPostTreatments'}->{'total'}++;
			if ($patientDiedFixed) {
				$statistics{'breastMilkExposuresPostTreatments'}->{'bySeriousness'}->{'deaths'}->{'total'}++;
			} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
				$statistics{'breastMilkExposuresPostTreatments'}->{'bySeriousness'}->{'serious'}->{'total'}++;
			} else {
				$statistics{'breastMilkExposuresPostTreatments'}->{'bySeriousness'}->{'nonSerious'}->{'total'}++;
			}
			$statistics{'breastMilkExposuresPostTreatments'}->{'byCountries'}->{$countryName}->{'total'}++;
			if ($patientDiedFixed) {
				$statistics{'breastMilkExposuresPostTreatments'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'deaths'}->{'total'}++;
			} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
				$statistics{'breastMilkExposuresPostTreatments'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'serious'}->{'total'}++;
			} else {
				$statistics{'breastMilkExposuresPostTreatments'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'nonSerious'}->{'total'}++;
			}
			if ($countryName eq 'United States of America') {
				unless ($countryStateName) {
					$countryStateName = 'Unknown';
					$countryStateId = 19;
				}
				$statistics{'breastMilkExposuresPostTreatments'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'total'}++;
				if ($patientDiedFixed) {
					$statistics{'breastMilkExposuresPostTreatments'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'deaths'}->{'total'}++;
				} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
					$statistics{'breastMilkExposuresPostTreatments'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'serious'}->{'total'}++;
				} else {
					$statistics{'breastMilkExposuresPostTreatments'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'nonSerious'}->{'total'}++;
				}
			}
			my $breastMilkExposurePostTreatment = %$tb{$reportId}->{'breastMilkExposurePostTreatment'};
			if (defined $breastMilkExposurePostTreatment) {
				$statistics{'breastMilkExposuresPostTreatments'}->{'reviewed'}++;
				if ($patientDiedFixed) {
					$statistics{'breastMilkExposuresPostTreatments'}->{'bySeriousness'}->{'deaths'}->{'reviewed'}++;
				} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
					$statistics{'breastMilkExposuresPostTreatments'}->{'bySeriousness'}->{'serious'}->{'reviewed'}++;
				} else {
					$statistics{'breastMilkExposuresPostTreatments'}->{'bySeriousness'}->{'nonSerious'}->{'reviewed'}++;
				}
				$statistics{'breastMilkExposuresPostTreatments'}->{'byCountries'}->{$countryName}->{'reviewed'}++;
				if ($patientDiedFixed) {
					$statistics{'breastMilkExposuresPostTreatments'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'deaths'}->{'reviewed'}++;
				} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
					$statistics{'breastMilkExposuresPostTreatments'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'serious'}->{'reviewed'}++;
				} else {
					$statistics{'breastMilkExposuresPostTreatments'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'nonSerious'}->{'reviewed'}++;
				}
				if ($countryName eq 'United States of America') {
					unless ($countryStateName) {
						$countryStateName = 'Unknown';
						$countryStateId = 19;
					}
					$statistics{'breastMilkExposuresPostTreatments'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'reviewed'}++;
					if ($patientDiedFixed) {
						$statistics{'breastMilkExposuresPostTreatments'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'deaths'}->{'reviewed'}++;
					} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
						$statistics{'breastMilkExposuresPostTreatments'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'serious'}->{'reviewed'}++;
					} else {
						$statistics{'breastMilkExposuresPostTreatments'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'nonSerious'}->{'reviewed'}++;
					}
				}
	        	$breastMilkExposurePostTreatment = unpack("N", pack("B32", substr("0" x 32 . $breastMilkExposurePostTreatment, -32)));
	        	if ($breastMilkExposurePostTreatment) {
					$statistics{'breastMilkExposuresPostTreatments'}->{'confirmed'}++;
					if ($patientDiedFixed) {
						$statistics{'breastMilkExposuresPostTreatments'}->{'bySeriousness'}->{'deaths'}->{'confirmed'}++;
					} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
						$statistics{'breastMilkExposuresPostTreatments'}->{'bySeriousness'}->{'serious'}->{'confirmed'}++;
					} else {
						$statistics{'breastMilkExposuresPostTreatments'}->{'bySeriousness'}->{'nonSerious'}->{'confirmed'}++;
					}
					$statistics{'breastMilkExposuresPostTreatments'}->{'byCountries'}->{$countryName}->{'confirmed'}++;
					if ($patientDiedFixed) {
						$statistics{'breastMilkExposuresPostTreatments'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'deaths'}->{'confirmed'}++;
					} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
						$statistics{'breastMilkExposuresPostTreatments'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'serious'}->{'confirmed'}++;
					} else {
						$statistics{'breastMilkExposuresPostTreatments'}->{'byCountries'}->{$countryName}->{'bySeriousness'}->{'nonSerious'}->{'confirmed'}++;
					}
					if ($countryName eq 'United States of America') {
						unless ($countryStateName) {
							$countryStateName = 'Unknown';
							$countryStateId = 19;
						}
						$statistics{'breastMilkExposuresPostTreatments'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'confirmed'}++;
						if ($patientDiedFixed) {
							$statistics{'breastMilkExposuresPostTreatments'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'deaths'}->{'confirmed'}++;
						} elsif ($hospitalizedFixed || $lifeThreatningFixed || $permanentDisabilityFixed) {
							$statistics{'breastMilkExposuresPostTreatments'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'serious'}->{'confirmed'}++;
						} else {
							$statistics{'breastMilkExposuresPostTreatments'}->{'byCountries'}->{$countryName}->{'byStates'}->{$countryStateName}->{'bySeriousness'}->{'nonSerious'}->{'confirmed'}++;
						}
					}
	        	}
			}
		}
	}

	open my $out, '>:utf8', $completionStatsFile;
	print $out encode_json\%statistics;
	close $out;
	my $sth = $self->dbh->prepare("UPDATE software SET latestCountriesStatsUpdateTimestamp = $currentTimestamp WHERE name = ?");
	$sth->execute($softwareName) or die $sth->err();
	# p%statistics;
}

sub load_countries_and_states_data {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // die;
    my $wizardSelected  = $self->param('wizardSelected') // die;

	say "currentLanguage : $currentLanguage";
	say "wizardSelected  : $wizardSelected";

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    # Fetching completion statistics.
    my $json;
    open my $in, '<:utf8', $completionStatsFile;
    while (<$in>) {
    	$json .= $_;
    }
    close $in;
    $json = decode_json($json);
    my %statistics = %$json;
    %statistics = %{$statistics{$wizardSelected}};
    # p%statistics;

    $self->render(
        currentLanguage => $currentLanguage,
        languages => \%languages,
        statistics => \%statistics
    );
}

sub load_wizard_scope {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // die;
    my $wizardSelected  = $self->param('wizardSelected')  // die;
    my $scope           = $self->param('scope')           // die;
    my $countryName     = $self->param('countryName')     // die;

	say "currentLanguage : $currentLanguage";
	say "wizardSelected  : $wizardSelected";
	say "countryName     : $countryName";
	say "scope           : $scope";
	my $countryId;
	if ($countryName ne 'Unknown Country') {
		$countryId = country::country_id_from_name($self->dbh, $countryName);
	}
	if ($wizardSelected eq 'patientAgesConfirmations') {

        # Truncating age_wizard_report table.
        my $sth = $self->dbh->prepare("TRUNCATE age_wizard_report");
        $sth->execute() or die $sth->err();
        generate_ages_batch($self, $countryId, $scope);
	} elsif ($wizardSelected eq 'pregnanciesConfirmations') {

        # Truncating pregnancy_wizard_report table.
        my $sth = $self->dbh->prepare("TRUNCATE pregnancy_wizard_report");
        $sth->execute() or die $sth->err();
        generate_pregnancies_batch($self, $countryId, $scope);
	} elsif ($wizardSelected eq 'breastMilkExposuresConfirmations') {

        # Truncating breast_milk_wizard_report table.
        my $sth = $self->dbh->prepare("TRUNCATE breast_milk_wizard_report");
        $sth->execute() or die $sth->err();
        generate_breast_milk_batch($self, $countryId, $scope);
	} elsif ($wizardSelected eq 'pregnanciesSeriousnessConfirmations') {

        # Truncating breast_milk_wizard_report table.
        my $sth = $self->dbh->prepare("TRUNCATE pregnancy_seriousness_wizard_report");
        $sth->execute() or die $sth->err();
        generate_pregnancies_seriousness_batch($self, $countryId, $scope);
	} elsif ($wizardSelected eq 'breastMilkExposuresPostTreatments') {

        # Truncating breast_milk_wizard_report table.
        my $sth = $self->dbh->prepare("TRUNCATE breast_milk_post_treatment_wizard_report");
        $sth->execute() or die $sth->err();
        generate_breast_milk_post_treatment_batch($self, $countryId, $scope);
	} else {
		die "wizardSelected : [$wizardSelected]";
	}


    $self->render(
        text => 'ok'
    );
}

sub generate_breast_milk_batch {
    my ($self, $countryId, $scope) = @_;
    # Fetching total operations to perform.
    my $tb = $self->dbh->selectrow_hashref("SELECT count(id) as operationsToPerform FROM report WHERE breastMilkExposureConfirmationRequired = 1 AND breastMilkExposureConfirmation IS NULL", undef);
    my $operationsToPerform = %$tb{'operationsToPerform'} // die;
    if ($operationsToPerform) {
        # Generating current treatment batch.
        my $currentBatch = 0;
        my $sql;
        if ($countryId) {
	        $sql                 = "
	            SELECT
	                id as reportId,
	                breastMilkExposureConfirmation,
	                breastMilkExposureConfirmationRequired,
	                breastMilkExposureConfirmationTimestamp
	            FROM report
	            WHERE 
	                breastMilkExposureConfirmationRequired = 1 AND
	                breastMilkExposureConfirmation IS NULL AND
	                countryId = $countryId";
    	} else {
	        $sql                 = "
	            SELECT
	                id as reportId,
	                breastMilkExposureConfirmation,
	                breastMilkExposureConfirmationRequired,
	                breastMilkExposureConfirmationTimestamp
	            FROM report
	            WHERE 
	                breastMilkExposureConfirmationRequired = 1 AND
	                breastMilkExposureConfirmation IS NULL AND
	                countryId IS NULL";
    	}
    	if ($scope eq 'deaths') {
    		$sql .= " AND patientDiedFixed = 1";
		} elsif ($scope eq 'serious') {
    		$sql .= " AND (patientDiedFixed = 1 OR permanentDisabilityFixed = 1 OR hospitalizedFixed = 1)";
		}
    	$sql .= "
	            ORDER BY RAND()
	            LIMIT $treatmentLimit";
        say "$sql";
        my $rTb                 = $self->dbh->selectall_hashref($sql, 'reportId'); # ORDER BY RAND()
        for my $reportId (sort{$a <=> $b} keys %$rTb) {
            my $breastMilkExposureConfirmationRequired       = %$rTb{$reportId}->{'breastMilkExposureConfirmationRequired'} // die;
            $breastMilkExposureConfirmationRequired          = unpack("N", pack("B32", substr("0" x 32 . $breastMilkExposureConfirmationRequired, -32)));
            my $breastMilkExposureConfirmation               = %$rTb{$reportId}->{'breastMilkExposureConfirmation'};
            # $breastMilkExposureConfirmation                  = unpack("N", pack("B32", substr("0" x 32 . $breastMilkExposureConfirmation, -32)));
            my $breastMilkExposureConfirmationTimestamp      = %$rTb{$reportId}->{'breastMilkExposureConfirmationTimestamp'};
            my $sth = $self->dbh->prepare("INSERT INTO breast_milk_wizard_report (reportId, breastMilkExposureConfirmationRequired, breastMilkExposureConfirmation, breastMilkExposureConfirmationTimestamp) VALUES (?, $breastMilkExposureConfirmationRequired, NULL, ?)");
            $sth->execute($reportId, $breastMilkExposureConfirmationTimestamp) or die $sth->err();
            $currentBatch++;
        }
        $operationsToPerform = $currentBatch;
    }
    return $operationsToPerform;
}

sub generate_breast_milk_post_treatment_batch {
    my ($self, $countryId, $scope) = @_;
    # Fetching total operations to perform.
    my $tb = $self->dbh->selectrow_hashref("SELECT count(id) as operationsToPerform FROM report WHERE breastMilkExposurePostTreatmentRequired = 1 AND breastMilkExposurePostTreatment IS NULL", undef);
    my $operationsToPerform = %$tb{'operationsToPerform'} // die;
    if ($operationsToPerform) {
        # Generating current treatment batch.
        my $currentBatch = 0;
        my $sql;
        if ($countryId) {
	        $sql                 = "
	            SELECT
	                id as reportId,
	                breastMilkExposurePostTreatment,
	                breastMilkExposurePostTreatmentRequired,
	                breastMilkExposurePostTreatmentTimestamp
	            FROM report
	            WHERE 
	                breastMilkExposurePostTreatmentRequired = 1 AND
	                breastMilkExposurePostTreatment IS NULL AND
	                countryId = $countryId";
    	} else {
	        $sql                 = "
	            SELECT
	                id as reportId,
	                breastMilkExposurePostTreatment,
	                breastMilkExposurePostTreatmentRequired,
	                breastMilkExposurePostTreatmentTimestamp
	            FROM report
	            WHERE 
	                breastMilkExposurePostTreatmentRequired = 1 AND
	                breastMilkExposurePostTreatment IS NULL AND
	                countryId IS NULL";
    	}
    	if ($scope eq 'deaths') {
    		$sql .= " AND patientDiedFixed = 1";
		} elsif ($scope eq 'serious') {
    		$sql .= " AND (patientDiedFixed = 1 OR permanentDisabilityFixed = 1 OR hospitalizedFixed = 1)";
		}
    	$sql .= "
	            ORDER BY RAND()
	            LIMIT $treatmentLimit";
        say "$sql";
        my $rTb                 = $self->dbh->selectall_hashref($sql, 'reportId'); # ORDER BY RAND()
        for my $reportId (sort{$a <=> $b} keys %$rTb) {
            my $breastMilkExposurePostTreatmentRequired  = %$rTb{$reportId}->{'breastMilkExposurePostTreatmentRequired'} // die;
            $breastMilkExposurePostTreatmentRequired     = unpack("N", pack("B32", substr("0" x 32 . $breastMilkExposurePostTreatmentRequired, -32)));
            my $breastMilkExposurePostTreatment          = %$rTb{$reportId}->{'breastMilkExposurePostTreatment'};
            # $breastMilkExposurePostTreatment             = unpack("N", pack("B32", substr("0" x 32 . $breastMilkExposurePostTreatment, -32)));
            my $breastMilkExposurePostTreatmentTimestamp = %$rTb{$reportId}->{'breastMilkExposurePostTreatmentTimestamp'};
            my $sth = $self->dbh->prepare("INSERT INTO breast_milk_post_treatment_wizard_report (reportId, breastMilkExposurePostTreatmentRequired, breastMilkExposurePostTreatment, breastMilkExposurePostTreatmentTimestamp) VALUES (?, $breastMilkExposurePostTreatmentRequired, NULL, ?)");
            $sth->execute($reportId, $breastMilkExposurePostTreatmentTimestamp) or die $sth->err();
            $currentBatch++;
        }
        $operationsToPerform = $currentBatch;
    }
    return $operationsToPerform;
}

sub generate_ages_batch {
    my ($self, $countryId, $scope) = @_;
    # Fetching total operations to perform.
    my $tb = $self->dbh->selectrow_hashref("SELECT count(id) as operationsToPerform FROM report WHERE patientAgeConfirmationRequired = 1 AND patientAgeConfirmation IS NULL", undef);
    my $operationsToPerform = %$tb{'operationsToPerform'} // die;
    if ($operationsToPerform) {
        # Generating current treatment batch.
        my $currentBatch = 0;
        my $sql;
        if ($countryId) {
	        $sql                 = "
            SELECT
                id as reportId,
                patientAgeConfirmation,
                patientAgeConfirmationRequired,
                patientAgeConfirmationTimestamp
            FROM report
            WHERE 
                patientAgeConfirmationRequired = 1 AND
                patientAgeConfirmation IS NULL AND
                countryId = $countryId";
    	} else {
	        $sql                 = "
            SELECT
                id as reportId,
                patientAgeConfirmation,
                patientAgeConfirmationRequired,
                patientAgeConfirmationTimestamp
            FROM report
            WHERE 
                patientAgeConfirmationRequired = 1 AND
                patientAgeConfirmation IS NULL AND
                countryId IS NULL";
    	}
    	if ($scope eq 'deaths') {
    		$sql .= " AND patientDiedFixed = 1";
		} elsif ($scope eq 'serious') {
    		$sql .= " AND (patientDiedFixed = 1 OR permanentDisabilityFixed = 1 OR hospitalizedFixed = 1)";
		}
    	$sql .= "
	            ORDER BY RAND()
	            LIMIT $treatmentLimit";
        my $rTb                 = $self->dbh->selectall_hashref($sql, 'reportId'); # ORDER BY RAND()
        for my $reportId (sort{$a <=> $b} keys %$rTb) {
            my $patientAgeConfirmationRequired       = %$rTb{$reportId}->{'patientAgeConfirmationRequired'} // die;
            $patientAgeConfirmationRequired          = unpack("N", pack("B32", substr("0" x 32 . $patientAgeConfirmationRequired, -32)));
            my $patientAgeConfirmation               = %$rTb{$reportId}->{'patientAgeConfirmation'};
            # $patientAgeConfirmation                  = unpack("N", pack("B32", substr("0" x 32 . $patientAgeConfirmation, -32)));
            my $patientAgeConfirmationTimestamp      = %$rTb{$reportId}->{'patientAgeConfirmationTimestamp'};
            my $sth = $self->dbh->prepare("INSERT INTO age_wizard_report (reportId, patientAgeConfirmationRequired, patientAgeConfirmation, patientAgeConfirmationTimestamp) VALUES (?, $patientAgeConfirmationRequired, NULL, ?)");
            $sth->execute($reportId, $patientAgeConfirmationTimestamp) or die $sth->err();
            $currentBatch++;
        }
        $operationsToPerform = $currentBatch;
    }
    return $operationsToPerform;
}

sub generate_pregnancies_batch {
    my ($self, $countryId, $scope) = @_;
    # Fetching total operations to perform.
    my $tb = $self->dbh->selectrow_hashref("SELECT count(id) as operationsToPerform FROM report WHERE pregnancyConfirmationRequired = 1 AND pregnancyConfirmation IS NULL", undef);
    my $operationsToPerform = %$tb{'operationsToPerform'} // die;
    if ($operationsToPerform) {
        # Generating current treatment batch.
        my $currentBatch = 0;
        my $sql;
        if ($countryId) {
	        $sql                 = "
            SELECT
                id as reportId,
                pregnancyConfirmation,
                pregnancyConfirmationRequired,
                pregnancyConfirmationTimestamp
            FROM report
            WHERE 
                pregnancyConfirmationRequired = 1 AND
                pregnancyConfirmation IS NULL AND
                countryId = $countryId";
    	} else {
	        $sql                 = "
            SELECT
                id as reportId,
                pregnancyConfirmation,
                pregnancyConfirmationRequired,
                pregnancyConfirmationTimestamp
            FROM report
            WHERE 
                pregnancyConfirmationRequired = 1 AND
                pregnancyConfirmation IS NULL AND
                countryId IS NULL";
    	}
    	if ($scope eq 'deaths') {
    		$sql .= " AND patientDiedFixed = 1";
		} elsif ($scope eq 'serious') {
    		$sql .= " AND (patientDiedFixed = 1 OR permanentDisabilityFixed = 1 OR hospitalizedFixed = 1)";
		}
    	$sql .= "
	            ORDER BY RAND()
	            LIMIT $treatmentLimit";
        say "$sql";
        my $rTb                 = $self->dbh->selectall_hashref($sql, 'reportId'); # ORDER BY RAND()
        for my $reportId (sort{$a <=> $b} keys %$rTb) {
            my $pregnancyConfirmationRequired       = %$rTb{$reportId}->{'pregnancyConfirmationRequired'} // die;
            $pregnancyConfirmationRequired          = unpack("N", pack("B32", substr("0" x 32 . $pregnancyConfirmationRequired, -32)));
            my $pregnancyConfirmation               = %$rTb{$reportId}->{'pregnancyConfirmation'};
            # $pregnancyConfirmation                  = unpack("N", pack("B32", substr("0" x 32 . $pregnancyConfirmation, -32)));
            my $pregnancyConfirmationTimestamp      = %$rTb{$reportId}->{'pregnancyConfirmationTimestamp'};
            my $sth = $self->dbh->prepare("INSERT INTO pregnancy_wizard_report (reportId, pregnancyConfirmationRequired, pregnancyConfirmation, pregnancyConfirmationTimestamp) VALUES (?, $pregnancyConfirmationRequired, NULL, ?)");
            $sth->execute($reportId, $pregnancyConfirmationTimestamp) or die $sth->err();
            $currentBatch++;
        }
        say "currentBatch : $currentBatch";
        $operationsToPerform = $currentBatch;
    }
    return $operationsToPerform;
}

sub generate_pregnancies_seriousness_batch {
    my ($self, $countryId, $scope) = @_;
    # Fetching total operations to perform.
    my $tb = $self->dbh->selectrow_hashref("SELECT count(id) as operationsToPerform FROM report WHERE pregnancySeriousnessConfirmationRequired = 1 AND pregnancySeriousnessConfirmation IS NULL", undef);
    my $operationsToPerform = %$tb{'operationsToPerform'} // die;
    if ($operationsToPerform) {
        # Generating current treatment batch.
        my $currentBatch = 0;
        my $sql;
        if ($countryId) {
	        $sql                 = "
            SELECT
                id as reportId,
                pregnancySeriousnessConfirmation,
                pregnancySeriousnessConfirmationRequired,
                pregnancySeriousnessConfirmationTimestamp
            FROM report
            WHERE 
                pregnancySeriousnessConfirmationRequired = 1 AND
                pregnancySeriousnessConfirmation IS NULL AND
                countryId = $countryId";
    	} else {
	        $sql                 = "
            SELECT
                id as reportId,
                pregnancySeriousnessConfirmation,
                pregnancySeriousnessConfirmationRequired,
                pregnancySeriousnessConfirmationTimestamp
            FROM report
            WHERE 
                pregnancySeriousnessConfirmationRequired = 1 AND
                pregnancySeriousnessConfirmation IS NULL AND
                countryId IS NULL";
    	}
    	if ($scope eq 'deaths') {
    		$sql .= " AND patientDiedFixed = 1";
		} elsif ($scope eq 'serious') {
    		$sql .= " AND (patientDiedFixed = 1 OR permanentDisabilityFixed = 1 OR hospitalizedFixed = 1)";
		}
    	$sql .= "
	            ORDER BY RAND()
	            LIMIT $treatmentLimit";
        say "$sql";
        my $rTb                 = $self->dbh->selectall_hashref($sql, 'reportId'); # ORDER BY RAND()
        for my $reportId (sort{$a <=> $b} keys %$rTb) {
            my $pregnancySeriousnessConfirmationRequired       = %$rTb{$reportId}->{'pregnancySeriousnessConfirmationRequired'} // die;
            $pregnancySeriousnessConfirmationRequired          = unpack("N", pack("B32", substr("0" x 32 . $pregnancySeriousnessConfirmationRequired, -32)));
            my $pregnancySeriousnessConfirmation               = %$rTb{$reportId}->{'pregnancySeriousnessConfirmation'};
            # $pregnancySeriousnessConfirmation                  = unpack("N", pack("B32", substr("0" x 32 . $pregnancySeriousnessConfirmation, -32)));
            my $pregnancySeriousnessConfirmationTimestamp      = %$rTb{$reportId}->{'pregnancySeriousnessConfirmationTimestamp'};
            my $sth = $self->dbh->prepare("INSERT INTO pregnancy_seriousness_wizard_report (reportId, pregnancySeriousnessConfirmationRequired, pregnancySeriousnessConfirmation, pregnancySeriousnessConfirmationTimestamp) VALUES (?, $pregnancySeriousnessConfirmationRequired, NULL, ?)");
            $sth->execute($reportId, $pregnancySeriousnessConfirmationTimestamp) or die $sth->err();
            $currentBatch++;
        }
        $operationsToPerform = $currentBatch;
    }
    return $operationsToPerform;
}

1;