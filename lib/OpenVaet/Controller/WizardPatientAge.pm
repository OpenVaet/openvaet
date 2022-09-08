package OpenVaet::Controller::WizardPatientAge;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Data::Printer;
use Math::Round qw(nearest);
use FindBin;
use lib "$FindBin::Bin/../lib";
use session;

sub wizard_patient_age {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'fr';
    my $dataType = $self->param('dataType') // die;
    my $table;
    if ($dataType eq 'domestic') {
        $table = 'vaers_deaths_report';
    } elsif ($dataType eq 'foreign') {
        $table = 'vaers_foreign_report';
    } else {
        die "dataType : $dataType";
    }

    # Loggin session if unknown.
    session::session_from_self($self);

    # Fetching total operations to perform.
    my $tb = $self->dbh->selectrow_hashref("SELECT count(id) as operationsToPerform FROM $table WHERE patientAgeConfirmationRequired = 1 AND patientAgeConfirmationTimestamp IS NULL", undef);
    my $operationsToPerform = %$tb{'operationsToPerform'} // die;

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    $self->render(
        currentLanguage => $currentLanguage,
        dataType => $dataType,
        operationsToPerform => $operationsToPerform,
        languages => \%languages
    );
}

sub load_next_report {
    my $self = shift;

    # Loggin session if unknown.
    session::session_from_self($self);
    my %enums = %{$self->enums()};

    # Setting language & lang options.
    my $currentLanguage = $self->param('currentLanguage') // die;
    my $dataType            = $self->param('dataType')            // die;
    my $table;
    if ($dataType eq 'domestic') {
        $table = 'vaers_deaths_report';
    } elsif ($dataType eq 'foreign') {
        $table = 'vaers_foreign_report';
    } else { die "table : $table" }
    my %languages       = ();
    $languages{'fr'}    = 'French';
    $languages{'en'}    = 'English';
    my %config          = %{$self->config()};
    my $environment     = $config{'environment'} // die;

    # Fetching vaers symptoms.
    my %symptoms = ();
    my $sTb = $self->dbh->selectall_hashref("SELECT id as symptomId, name as symptomName, discarded FROM vaers_deaths_symptom", 'symptomId');
    for my $symptomId (sort{$a <=> $b} keys %$sTb) {
        my $symptomName = %$sTb{$symptomId}->{'symptomName'} // die;
        my $discarded   = %$sTb{$symptomId}->{'discarded'}   // die;
        $discarded      = unpack("N", pack("B32", substr("0" x 32 . $discarded, -32)));
        $symptoms{$symptomId}->{'symptomName'} = $symptomName;
        $symptoms{$symptomId}->{'discarded'}   = $discarded;
    }

    # Fetching confirmation target.
    # Fetching total operations to perform.
    my $tbT = $self->dbh->selectrow_hashref("SELECT count(id) as operationsToPerform FROM $table WHERE patientAgeConfirmationRequired = 1 AND patientAgeConfirmationTimestamp IS NULL", undef);
    my $operationsToPerform = %$tbT{'operationsToPerform'} // die;

    my ($hospitalized, $permanentDisability, $lifeThreatning, $patientDied, $reportId,
        $vaersId, $symptoms, $vaccinesListed, $vaersReceptionDate, $vaccinationDate,
        $vaccinationDateFixed, $vaccinationYear, $vaccinationMonth, $vaccinationDay, $onsetDate,
        $onsetDateFixed, $onsetYear, $onsetMonth, $onsetDay, $products,
        $deceasedYear, $deceasedMonth, $deceasedDay, $deceasedDate, $vaersSexFixed,
        $vaersSexName, $aEDescription, $patientAgeFixed, $creationDatetime, $hoursBetweenVaccineAndAE,
        $patientAgeConfirmation, $patientAgeConfirmationRequired);
    my $sqlParam            = 'patientAgeConfirmationRequired';
    my $sqlValue            = 'patientAgeConfirmation';
    if ($operationsToPerform) {
        my $sql                 = "
            SELECT
                id as reportId,
                vaersId,
                vaccinesListed,
                vaersSexFixed,
                patientAgeFixed,
                creationTimestamp,
                aEDescription,
                vaersReceptionDate,
                onsetDate,
                deceasedDate,
                vaccinationDateFixed,
                onsetDateFixed,
                vaccinationDate,
                vaccinesListed,
                patientAgeConfirmation,
                patientAgeConfirmationRequired,
                hoursBetweenVaccineAndAE,
                hospitalized,
                permanentDisability,
                lifeThreatning,
                patientDied,
                symptomsListed
            FROM $table
            WHERE
                $sqlValue IS NULL AND
                $sqlParam = 1 ORDER BY RAND()
            LIMIT 1";
        say "$sql";
        my $rTb                 = $self->dbh->selectrow_hashref($sql, undef); # ORDER BY RAND()
        $reportId                             = %$rTb{'reportId'}                        // die;
        $vaersId                              = %$rTb{'vaersId'}                         // die;
        $vaccinesListed                       = %$rTb{'vaccinesListed'}                  // die;
        $vaersSexFixed                        = %$rTb{'vaersSexFixed'}                   // die;
        $vaersSexName                         = $enums{'vaersSex'}->{$vaersSexFixed}     // die;
        $patientAgeFixed                      = %$rTb{'patientAgeFixed'};
        $hoursBetweenVaccineAndAE             = %$rTb{'hoursBetweenVaccineAndAE'};
        my $creationTimestamp                 = %$rTb{'creationTimestamp'}               // die;
        $creationDatetime                     = time::timestamp_to_datetime($creationTimestamp);
        $aEDescription                        = %$rTb{'aEDescription'}                   // die;
        $vaersReceptionDate                   = %$rTb{'vaersReceptionDate'}              // die;
        $patientAgeConfirmationRequired = %$rTb{'patientAgeConfirmationRequired'} // die;
        $patientAgeConfirmationRequired    = unpack("N", pack("B32", substr("0" x 32 . $patientAgeConfirmationRequired, -32)));
        $hospitalized                         = %$rTb{'hospitalized'}        // die;
        $hospitalized                            = unpack("N", pack("B32", substr("0" x 32 . $hospitalized, -32)));
        $permanentDisability                  = %$rTb{'permanentDisability'} // die;
        $permanentDisability                     = unpack("N", pack("B32", substr("0" x 32 . $permanentDisability, -32)));
        $lifeThreatning                       = %$rTb{'lifeThreatning'}      // die;
        $lifeThreatning                          = unpack("N", pack("B32", substr("0" x 32 . $lifeThreatning, -32)));
        $patientDied                          = %$rTb{'patientDied'}         // die;
        $patientDied                             = unpack("N", pack("B32", substr("0" x 32 . $patientDied, -32)));
        $vaccinationDate                      = %$rTb{'vaccinationDate'};
        $onsetDate                            = %$rTb{'onsetDate'};
        $vaccinationDateFixed                 = %$rTb{'vaccinationDateFixed'};
        $onsetDateFixed                       = %$rTb{'onsetDateFixed'};
        $patientAgeConfirmation         = %$rTb{'patientAgeConfirmation'};
        $deceasedDate                              = %$rTb{'deceasedDate'};
        if ($deceasedDate) {
            ($deceasedYear, $deceasedMonth, $deceasedDay) = split '-', $deceasedDate;
        }
        $vaccinesListed = decode_json($vaccinesListed);
        for my $vaccineData (@$vaccinesListed) {
            my $substanceShortenedName = %$vaccineData{'substanceShortenedName'} // die;
            my $dose = %$vaccineData{'dose'} // die;
            $products .= "<li><span>$substanceShortenedName (dose $dose)</span></li>";
        }

        my @highlights = ('age', 'year', 'deceased', 'yo', 'week', 'day', 'old', 'decade');
        for my $hl (@highlights) {
            my $ucf = ucfirst $hl;
            my $uc = uc $hl;
            $aEDescription =~ s/$hl/\<span style=\"background:yellow;\"\>$hl\<\/span\>/g;
            $aEDescription =~ s/$ucf/\<span style=\"background:yellow;\"\>$ucf\<\/span\>/g;
            $aEDescription =~ s/$uc/\<span style=\"background:yellow;\"\>$uc\<\/span\>/g;
        }
        my $symptomsListed                = %$rTb{'symptomsListed'}  // die;
        $symptomsListed                   = decode_json($symptomsListed);
        $symptoms = '<div style="width:300px;margin:auto;"><ul>';
        for my $symptomId (@$symptomsListed) {
            my $symptomName = $symptoms{$symptomId}->{'symptomName'} // die;
            my $discarded   = $symptoms{$symptomId}->{'discarded'}   // die;
            $symptoms .= '<li><span>' . $symptomName . '</span></li>';
        }
        $symptoms .= '</ul></div>';
        if ($vaccinationDateFixed) {
            ($vaccinationYear, $vaccinationMonth, $vaccinationDay) = split '-', $vaccinationDateFixed;
        }
        if ($onsetDateFixed) {
            ($onsetYear, $onsetMonth, $onsetDay) = split '-', $onsetDateFixed;
        }
    }

    my %sexes = ();
    $sexes{'1'}->{'sexName'} = 'Female';
    $sexes{'2'}->{'sexName'} = 'Male';
    $sexes{'3'}->{'sexName'} = 'Unknown';

    say "reportId : $reportId";

    $self->render(
        dataType                           => $dataType,
        currentLanguage                => $currentLanguage,
        sqlValue                       => $sqlValue,
        operationsToPerform            => $operationsToPerform,
        hospitalized                   => $hospitalized,
        permanentDisability            => $permanentDisability,
        lifeThreatning                 => $lifeThreatning,
        patientDied                    => $patientDied,
        reportId                       => $reportId,
        vaersId                        => $vaersId,
        symptoms                       => $symptoms,
        vaccinesListed                 => $vaccinesListed,
        vaersReceptionDate             => $vaersReceptionDate,
        vaccinationDate                => $vaccinationDate,
        vaccinationDateFixed           => $vaccinationDateFixed,
        vaccinationYear                => $vaccinationYear,
        vaccinationMonth               => $vaccinationMonth,
        vaccinationDay                 => $vaccinationDay,
        onsetDate                      => $onsetDate,
        onsetDateFixed                 => $onsetDateFixed,
        onsetYear                      => $onsetYear,
        onsetMonth                     => $onsetMonth,
        onsetDay                       => $onsetDay,
        products                       => $products,
        deceasedYear                   => $deceasedYear,
        deceasedMonth                  => $deceasedMonth,
        deceasedDay                    => $deceasedDay,
        deceasedDate                   => $deceasedDate,
        vaersSexFixed                  => $vaersSexFixed,
        vaersSexName                   => $vaersSexName,
        aEDescription                  => $aEDescription,
        patientAgeFixed                => $patientAgeFixed,
        creationDatetime               => $creationDatetime,
        hoursBetweenVaccineAndAE       => $hoursBetweenVaccineAndAE,
        patientAgeConfirmation         => $patientAgeConfirmation,
        patientAgeConfirmationRequired => $patientAgeConfirmationRequired,
        sexes                          => \%sexes,
        languages                      => \%languages
    );
}

sub set_report_attribute {
    my $self              = shift;
    my $reportId          = $self->param('reportId')        // die;
    my $sqlValue          = $self->param('sqlValue')        // die;
    my $value             = $self->param('value')           // die;
    my $dataType              = $self->param('dataType') // die;
    my $table;
    if ($dataType eq 'domestic') {
        $table = 'vaers_deaths_report';
    } elsif ($dataType eq 'foreign') {
        $table = 'vaers_foreign_report';
    } else { die "table : $table" }
    my $userId            = $self->session('userId')        // die;
    my $patientAgeFixed   = $self->param('patientAgeFixed') // die;
    $patientAgeFixed      = undef unless length $patientAgeFixed    >= 1;
    my $vaersSexFixed     = $self->param('vaersSexFixed')   // die;
    my $vaccinationYear   = $self->param('vaccinationYear') // die;
    $vaccinationYear      = undef unless length $vaccinationYear    >= 1;
    my $vaccinationMonth   = $self->param('vaccinationMonth') // die;
    $vaccinationMonth      = undef unless length $vaccinationMonth    >= 1;
    my $vaccinationDay   = $self->param('vaccinationDay') // die;
    $vaccinationDay      = undef unless length $vaccinationDay    >= 1;
    my $deceasedYear   = $self->param('deceasedYear') // die;
    $deceasedYear      = undef unless length $deceasedYear    >= 1;
    my $deceasedMonth   = $self->param('deceasedMonth') // die;
    $deceasedMonth      = undef unless length $deceasedMonth    >= 1;
    my $deceasedDay   = $self->param('deceasedDay') // die;
    $deceasedDay      = undef unless length $deceasedDay    >= 1;
    my $onsetYear   = $self->param('onsetYear') // die;
    $onsetYear      = undef unless length $onsetYear    >= 1;
    my $onsetMonth   = $self->param('onsetMonth') // die;
    $onsetMonth      = undef unless length $onsetMonth    >= 1;
    my $onsetDay   = $self->param('onsetDay') // die;
    $onsetDay      = undef unless length $onsetDay    >= 1;
    my ($onsetDateFixed, $vaccinationDateFixed, $deceasedDateFixed);
    if ($vaccinationYear && $vaccinationMonth && $vaccinationDay) {
        $vaccinationDateFixed = "$vaccinationYear-$vaccinationMonth-$vaccinationDay";
    }
    if ($onsetYear && $onsetMonth && $onsetDay) {
        $onsetDateFixed = "$onsetYear-$onsetMonth-$onsetDay";
    }
    if ($deceasedYear && $deceasedMonth && $deceasedDay) {
        $deceasedDateFixed = "$deceasedYear-$deceasedMonth-$deceasedDay";
    }
    my $patientDied   = $self->param('patientDied') // die;
    my $lifeThreatning   = $self->param('lifeThreatning') // die;
    my $permanentDisability   = $self->param('permanentDisability') // die;
    my $hospitalized   = $self->param('hospitalized') // die;
    my $hoursBetweenVaccineAndAE   = $self->param('hoursBetweenVaccineAndAE') // die;
    $hoursBetweenVaccineAndAE      = undef unless length $hoursBetweenVaccineAndAE    >= 1;
    if ($onsetDateFixed && $vaccinationDateFixed && !defined $hoursBetweenVaccineAndAE) {
        $hoursBetweenVaccineAndAE = time::calculate_minutes_difference("$vaccinationDateFixed 12:00:00", "$onsetDateFixed 12:00:00");
        $hoursBetweenVaccineAndAE = nearest(0.01, ($hoursBetweenVaccineAndAE / 60));
    }
    my $sth = $self->dbh->prepare("
        UPDATE $table SET
            $sqlValue = $value,
            patientAgeFixed = ?,
            vaersSexFixed = ?,
            vaccinationDateFixed = ?,
            onsetDateFixed = ?,
            deceasedDateFixed = ?,
            hoursBetweenVaccineAndAE = ?,
            patientDiedFixed = $patientDied,
            lifeThreatningFixed = $lifeThreatning,
            permanentDisabilityFixed = $permanentDisability,
            hospitalizedFixed = $hospitalized,
            patientAgeConfirmationTimestamp = UNIX_TIMESTAMP(),
            userId = ?
        WHERE id = $reportId");
    $sth->execute(
        $patientAgeFixed,
        $vaersSexFixed,
        $vaccinationDateFixed,
        $onsetDateFixed,
        $deceasedDateFixed,
        $hoursBetweenVaccineAndAE,
        $userId
    ) or die $sth->err();

    say "reportId : $reportId";

    $self->render(text => 'ok');
}

sub patient_ages_completed {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // die;
    my $adminFilter     = $self->param('adminFilter');
    my $productFilter   = $self->param('productFilter');
    my $dataType = $self->param('dataType') // die;
    my $table;
    if ($dataType eq 'domestic') {
        $table = 'vaers_deaths_report';
    } elsif ($dataType eq 'foreign') {
        $table = 'vaers_foreign_report';
    } else {
        die "dataType : $dataType";
    }
    say "productFilter : $productFilter";

    # Loggin session if unknown.
    session::session_from_self($self);

    # Fetching total operations to perform.
    my %reports = ();
    my ($agesCompleted, $totalReports) = (0, 0);
    my %admins = ();
    my %products = ();
    my $tb = $self->dbh->selectall_hashref("
        SELECT
            $table.id as vaersReportId,
            $table.patientAgeFixed,
            $table.vaersId,
            $table.vaccinesListed,
            $table.patientAgeConfirmationTimestamp,
            $table.userId,
            user.email 
        FROM $table
            LEFT JOIN user ON user.id = $table.userId
        WHERE patientAgeConfirmationTimestamp IS NOT NULL
    ", 'vaersReportId');
    for my $vaersReportId (sort{$a <=> $b} keys %$tb) {
        my $patientAgeFixed                 = %$tb{$vaersReportId}->{'patientAgeFixed'};
        my $patientAgeConfirmationTimestamp = %$tb{$vaersReportId}->{'patientAgeConfirmationTimestamp'} // die;
        my $patientAgeConfirmationDatetime  = time::timestamp_to_datetime($patientAgeConfirmationTimestamp);
        my $userId                          = %$tb{$vaersReportId}->{'userId'}                          // die;
        my $vaersId                         = %$tb{$vaersReportId}->{'vaersId'}                         // die;
        my $email                           = %$tb{$vaersReportId}->{'email'}                           // die;
        my ($userName) = split '\@', $email;
        $admins{$userName} = 1;
        if ($adminFilter) {
            next if $userName ne $adminFilter;
        }
        my $vaccinesListed                  = %$tb{$vaersReportId}->{'vaccinesListed'}                  // die;
        $vaccinesListed = decode_json($vaccinesListed);
        my %vax = ();
        my $hasProduct = 0;
        for my $vaccineData (@$vaccinesListed) {
            my $substanceShortenedName = %$vaccineData{'substanceShortenedName'} // die;
            if ($productFilter) {
                $hasProduct = 1 if $substanceShortenedName eq $productFilter;
            }
            $vax{$substanceShortenedName} = 1;
            $products{$substanceShortenedName} = 1;
        }
        if ($productFilter) {
            next unless $hasProduct;
        }
        $agesCompleted++ if defined $patientAgeFixed;
        $totalReports++;
        for my $substanceShortenedName (sort keys %vax) {
            $reports{$patientAgeConfirmationTimestamp}->{$vaersReportId}->{'products'}->{$substanceShortenedName} = 1;
        }
        $reports{$patientAgeConfirmationTimestamp}->{$vaersReportId}->{'patientAgeConfirmationDatetime'} = $patientAgeConfirmationDatetime;
        $reports{$patientAgeConfirmationTimestamp}->{$vaersReportId}->{'patientAgeFixed'} = $patientAgeFixed;
        $reports{$patientAgeConfirmationTimestamp}->{$vaersReportId}->{'userName'} = $userName;
        $reports{$patientAgeConfirmationTimestamp}->{$vaersReportId}->{'vaersId'} = $vaersId;
    }
    my $agesCompletedPercent = 0;
    if ($totalReports) {
        $agesCompletedPercent = nearest(0.01, $agesCompleted * 100 / $totalReports);
    }

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    $self->render(
        currentLanguage => $currentLanguage,
        adminFilter => $adminFilter,
        dataType => $dataType,
        productFilter => $productFilter,
        agesCompleted => $agesCompleted,
        totalReports => $totalReports,
        agesCompletedPercent => $agesCompletedPercent,
        admins => \%admins,
        products => \%products,
        languages => \%languages,
        reports => \%reports
    );
}

sub reset_report_attributes {
    my $self = shift;
    my $vaersReportId = $self->param('vaersReportId') // die;
    my $dataType = $self->param('dataType') // die;
    my $table;
    if ($dataType eq 'domestic') {
        $table = 'vaers_deaths_report';
    } elsif ($dataType eq 'foreign') {
        $table = 'vaers_foreign_report';
    } else {
        die "dataType : $dataType";
    }

    say "vaersReportId : $vaersReportId";
    my $sth = $self->dbh->prepare("UPDATE $table SET patientAgeConfirmation = NULL, patientAgeConfirmationTimestamp = NULL, userId = NULL WHERE id = $vaersReportId");
    $sth->execute() or die $sth->err();

    $self->render(text => 'ok');
}

sub patient_ages_custom_export {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // die;

    # Loggin session if unknown.
    session::session_from_self($self);

    # Fetching total operations to perform.
    my %admins = ();
    my $tb = $self->dbh->selectall_hashref("
        SELECT
            DISTINCT(user.email) 
        FROM vaers_deaths_report
            LEFT JOIN user ON user.id = vaers_deaths_report.userId
        WHERE patientAgeConfirmationTimestamp IS NOT NULL
    ", 'email');
    for my $email (sort keys %$tb) {
        my ($userName) = split '\@', $email;
        $admins{$userName} = 1;
    }

    # Fetching vaers symptoms.
    my %symptoms = ();
    my $sTb = $self->dbh->selectall_hashref("SELECT id as symptomId, name as symptomName FROM vaers_deaths_symptom", 'symptomId');
    for my $symptomId (sort{$a <=> $b} keys %$sTb) {
        my $symptomName = %$sTb{$symptomId}->{'symptomName'} // die;
        $symptoms{$symptomName}->{'symptomId'} = $symptomId;
    }

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    my %products = ();
    $products{'COVID-19 VACCINE JANSSEN'}              = 'JANSSEN';
    $products{'COVID-19 VACCINE MODERNA'}              = 'MODERNA';
    $products{'COVID-19 VACCINE NOVAVAX'}              = 'NOVAVAX';
    $products{'COVID-19 VACCINE PFIZER-BIONTECH'}      = 'PFIZER';
    $products{'COVID-19 VACCINE UNKNOWN MANUFACTURER'} = 'UNKNOWN';

    my %severities = ();
    $severities{'1'}->{'label'} = 'Died';
    $severities{'1'}->{'value'} = 'patientDiedFixed';
    $severities{'2'}->{'label'} = 'Permanent Disability';
    $severities{'2'}->{'value'} = 'permanentDisabilityFixed';
    $severities{'3'}->{'label'} = 'Life Threatening';
    $severities{'3'}->{'value'} = 'lifeThreatningFixed';
    $severities{'4'}->{'label'} = 'Hospitalized';
    $severities{'4'}->{'value'} = 'hospitalizedFixed';

    $self->render(
        currentLanguage => $currentLanguage,
        products => \%products,
        languages => \%languages,
        symptoms => \%symptoms,
        severities => \%severities,
        admins => \%admins
    );
}

sub admin_custom_export {
    my $self   = shift;
    my $userId = $self->session('userId') // die;

    my $reports;
    open my $in, '<:utf8', "public/admin_exports/export_$userId.json";
    while (<$in>) {
        $reports .= $_;
    }
    close $in;
    $reports = decode_json($reports);
    my %reports = %$reports;


    $self->render(
        reports  => \%reports
    );
}

sub generate_products_export {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // die;

    my %enums = %{$self->enums()};

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';
    my $params = $self->req->params->names;
    p$params;

    my $userId           = $self->session('userId')         // die;
    my $janssen          = $self->param('janssen')          // die;
    my $moderna          = $self->param('moderna')          // die;
    my $novavax          = $self->param('novavax')          // die;
    my $pfizer           = $self->param('pfizer')           // die;
    my $unknown          = $self->param('unknown')          // die;
    my $adminFilter      = $self->param('adminFilter')      // die;
    my $symptomFilter    = $self->param('symptomFilter')    // die;
    my $severityFilter   = $self->param('severityFilter')   // die;
    my $ageErrorsOnly    = $self->param('ageErrorsOnly')    // die;
    my $ageCompletedOnly = $self->param('ageCompletedOnly') // die;
    say "ageErrorsOnly    : $ageErrorsOnly";
    say "ageCompletedOnly : $ageCompletedOnly";
    say "symptomFilter    : $symptomFilter";

    my %symptomsFiltered = ();
    if ($symptomFilter) {
        $symptomFilter   = decode_json($symptomFilter);
        for my $symptomId (@$symptomFilter) {
            next unless $symptomId;
            $symptomsFiltered{$symptomId} = 1;
        }
        $symptomFilter    = undef unless keys %symptomsFiltered;
    }

    # Listing products we look for.
    my %products = ();
    $products{'janssen'}->{'name'} = 'COVID-19 VACCINE JANSSEN';
    $products{'janssen'}->{'status'} = $janssen;
    $products{'moderna'}->{'name'} = 'COVID-19 VACCINE MODERNA';
    $products{'moderna'}->{'status'} = $moderna;
    $products{'novavax'}->{'name'} = 'COVID-19 VACCINE NOVAVAX';
    $products{'novavax'}->{'status'} = $novavax;
    $products{'pfizer'}->{'name'}  = 'COVID-19 VACCINE PFIZER-BIONTECH';
    $products{'pfizer'}->{'status'} = $pfizer;
    $products{'unknown'}->{'name'} = 'COVID-19 VACCINE UNKNOWN MANUFACTURER';
    $products{'unknown'}->{'status'} = $unknown;
    my %productsSearched = ();
    for my $productLabel (sort keys %products) {
        my $name = $products{$productLabel}->{'name'} // die;
        my $status = $products{$productLabel}->{'status'} // die;
        if ($status eq 'true') {
            $productsSearched{$name} = 1;
        }
    }

    # Fetching vaers symptoms.
    my %symptoms = ();
    my $sTb = $self->dbh->selectall_hashref("SELECT id as symptomId, name as symptomName, discarded FROM vaers_deaths_symptom", 'symptomId');
    for my $symptomId (sort{$a <=> $b} keys %$sTb) {
        my $symptomName = %$sTb{$symptomId}->{'symptomName'} // die;
        my $discarded   = %$sTb{$symptomId}->{'discarded'}   // die;
        $discarded      = unpack("N", pack("B32", substr("0" x 32 . $discarded, -32)));
        $symptoms{$symptomId}->{'symptomName'} = $symptomName;
        $symptoms{$symptomId}->{'discarded'}   = $discarded;
    }
    p%productsSearched;

    # Fetching all the reports corresponding to the selected manufacturer.
    my %reports = ();
    my $exported = 0;
    my $sql = "
        SELECT
            vaers_deaths_report.id as vaersDeathsReportId,
            vaers_deaths_report.vaersId,
            vaers_deaths_report.vaccinesListed,
            vaers_deaths_report.aEDescription,
            vaers_deaths_report.vaersSexFixed,
            vaers_deaths_report.cdcStateId,
            cdc_state.name as cdcStateName,
            vaers_deaths_report.onsetDateFixed,
            vaers_deaths_report.deceasedDateFixed,
            vaers_deaths_report.vaccinationDateFixed,
            vaers_deaths_report.vaersReceptionDate,
            vaers_deaths_report.patientAgeFixed,
            vaers_deaths_report.patientAge,
            vaers_deaths_report.symptomsListed,
            vaers_deaths_report.hospitalizedFixed,
            vaers_deaths_report.lifeThreatningFixed,
            vaers_deaths_report.permanentDisabilityFixed,
            vaers_deaths_report.patientDiedFixed,
            vaers_deaths_report.patientAgeConfirmationRequired,
            user.email 
        FROM vaers_deaths_report
            LEFT JOIN user ON user.id = vaers_deaths_report.userId
            LEFT JOIN cdc_state ON cdc_state.id = vaers_deaths_report.cdcStateId
        ";
    if ($severityFilter) {
        $sql .= " WHERE vaers_deaths_report.$severityFilter = 1";
    }
    my $tb = $self->dbh->selectall_hashref($sql, 'vaersDeathsReportId');
    for my $vaersDeathsReportId (sort{$a <=> $b} keys %$tb) {
        my $vaccinesListed = %$tb{$vaersDeathsReportId}->{'vaccinesListed'} // die;
        my $patientAgeFixed = %$tb{$vaersDeathsReportId}->{'patientAgeFixed'};
        my $patientAgeConfirmationRequired = %$tb{$vaersDeathsReportId}->{'patientAgeConfirmationRequired'} // die;
        $patientAgeConfirmationRequired    = unpack("N", pack("B32", substr("0" x 32 . $patientAgeConfirmationRequired, -32)));
        if ($ageErrorsOnly eq 'true') {
            next if $patientAgeConfirmationRequired == 0;
        }
        if ($ageCompletedOnly eq 'true') {
            next unless defined $patientAgeFixed;
        }
        if ($patientAgeConfirmationRequired == 1) {
            my $email = %$tb{$vaersDeathsReportId}->{'email'} // next;
            my ($userName) = split '\@', $email;
            if ($adminFilter) {
                next if $userName ne $adminFilter;
            }
        }
        $vaccinesListed = decode_json($vaccinesListed);
        my $hasProduct  = 0;
        for my $vaccineData (@$vaccinesListed) {
            my $substanceShortenedName = %$vaccineData{'substanceShortenedName'} // die;
            if (exists $productsSearched{$substanceShortenedName}) {
                $hasProduct = 1;
                last;
            }
        }
        if ($hasProduct == 1) {
            my $vaersId = %$tb{$vaersDeathsReportId}->{'vaersId'} // die;
            my $vaersReceptionDate = %$tb{$vaersDeathsReportId}->{'vaersReceptionDate'} // die;
            my $aEDescription = %$tb{$vaersDeathsReportId}->{'aEDescription'} // die;
            my $immProjectNumber = %$tb{$vaersDeathsReportId}->{'immProjectNumber'};
            my $cdcStateName = %$tb{$vaersDeathsReportId}->{'cdcStateName'} // die;
            my $vaersSexFixed = %$tb{$vaersDeathsReportId}->{'vaersSexFixed'} // die;
            my $vaersSexName = $enums{'vaersSex'}->{$vaersSexFixed} // die;
            my $source = 'Domestic';
            my $patientAge = %$tb{$vaersDeathsReportId}->{'patientAgeFixed'};
            my $vaccinationDate = %$tb{$vaersDeathsReportId}->{'vaccinationDateFixed'};
            my $onsetDate = %$tb{$vaersDeathsReportId}->{'onsetDateFixed'};
            my $permanentDisability = %$tb{$vaersDeathsReportId}->{'permanentDisabilityFixed'} // die;
            my $hospitalized = %$tb{$vaersDeathsReportId}->{'hospitalizedFixed'} // die;
            my $patientDied = %$tb{$vaersDeathsReportId}->{'patientDiedFixed'} // die;
            my $lifeThreatning = %$tb{$vaersDeathsReportId}->{'lifeThreatningFixed'} // die;
            my $symptomsListed = %$tb{$vaersDeathsReportId}->{'symptomsListed'} // die;
            $symptomsListed = decode_json($symptomsListed);
            $hospitalized        = unpack("N", pack("B32", substr("0" x 32 . $hospitalized, -32)));
            $permanentDisability = unpack("N", pack("B32", substr("0" x 32 . $permanentDisability, -32)));
            $lifeThreatning      = unpack("N", pack("B32", substr("0" x 32 . $lifeThreatning, -32)));
            $patientDied         = unpack("N", pack("B32", substr("0" x 32 . $patientDied, -32)));
            my $compDate = $vaersReceptionDate;
            $compDate =~ s/\D//g;
            my %o = ();
            my $hasSymptom = 0;
            for my $symptomId (@$symptomsListed) {
                my $symptomName = $symptoms{$symptomId}->{'symptomName'} // die;
                $o{'symptoms'}->{$symptomName} = 1;
                if ($symptomFilter) {
                    $hasSymptom = 1 if exists $symptomsFiltered{$symptomId};
                }
            }
            if ($symptomFilter) {
                next unless $hasSymptom == 1;
            }
            $o{'vaersId'} = $vaersId;
            $o{'vaersReceptionDate'} = $vaersReceptionDate;
            $o{'aEDescription'} = $aEDescription;
            $o{'immProjectNumber'} = $immProjectNumber;
            $o{'cdcStateName'} = $cdcStateName;
            $o{'vaersSexName'} = $vaersSexName;
            $o{'source'} = $source;
            $o{'patientAge'} = $patientAge;
            $o{'vaccinationDate'} = $vaccinationDate;
            $o{'onsetDate'} = $onsetDate;
            $o{'permanentDisability'} = $permanentDisability;
            $o{'hospitalized'} = $hospitalized;
            $o{'patientDied'} = $patientDied;
            $o{'lifeThreatning'} = $lifeThreatning;
            for my $vaccineData (@$vaccinesListed) {
                push @{$o{'vaccines'}}, \%$vaccineData;
            }
            push @{$reports{$compDate}}, \%o;
            $exported++;
        }
    }
    open my $out, '>:utf8', "public/admin_exports/export_$userId.json";
    print $out encode_json\%reports;
    close $out;
    say "exported : $exported";

    $self->render(
        currentLanguage => $currentLanguage,
        exported => $exported,
        languages => \%languages
    );
}

1;