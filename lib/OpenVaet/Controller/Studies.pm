package OpenVaet::Controller::Studies;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Data::Printer;
use Math::Round qw(nearest);
use FindBin;
use lib "$FindBin::Bin/../lib";
use session;

sub studies {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'fr';

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    $self->render(
        currentLanguage => $currentLanguage,
        languages => \%languages
    );
}

sub pregnancies_confirmation {
    my $self = shift;

    # Loggin session if unknown.
    session::session_from_self($self);

    # Setting language & lang options.
    my $currentLanguage = $self->param('currentLanguage') // 'fr';
    my %languages       = ();
    $languages{'fr'}    = 'French';
    $languages{'en'}    = 'English';
    my %config          = %{$self->config()};
    my $environment     = $config{'environment'} // die;

    # Fetching confirmation target.
    my $confirmationTarget = $self->param('confirmationTarget') // die;

    # Fetching total operations to perform.
    my $operationsToPerform = 0;
    if ($confirmationTarget eq 'pregancies') {
        my $tb = $self->dbh->selectrow_hashref("SELECT count(id) as operationsToPerform FROM vaers_fertility_report WHERE pregnancyConfirmation IS NULL AND pregnancyConfirmationRequired = 1 AND (menstrualCycleDisordersConfirmation IS NULL OR menstrualCycleDisordersConfirmation != 1) AND (babyExposureConfirmation IS NULL OR babyExposureConfirmation != 1)", undef);
        $operationsToPerform = %$tb{'operationsToPerform'} // die;
    }

    $self->render(
        currentLanguage     => $currentLanguage,
        operationsToPerform => $operationsToPerform,
        confirmationTarget  => $confirmationTarget,
        environment         => $environment,
        languages           => \%languages
    );
}

sub load_pregnancy_confirmation {
    my $self = shift;

    # Loggin session if unknown.
    session::session_from_self($self);
    my %enums = %{$self->enums()};

    # Setting language & lang options.
    my $currentLanguage = $self->param('currentLanguage') // 'fr';
    my %languages       = ();
    $languages{'fr'}    = 'French';
    $languages{'en'}    = 'English';
    my %config          = %{$self->config()};
    my $environment     = $config{'environment'} // die;
    if ($environment ne "local") {
        $self->render(text => 'Disallowed');
    }

    # Fetching vaers symptoms.
    my %symptoms = ();
    my $sTb = $self->dbh->selectall_hashref("SELECT id as symptomId, name as symptomName, discarded FROM vaers_fertility_symptom", 'symptomId');
    for my $symptomId (sort{$a <=> $b} keys %$sTb) {
        my $symptomName = %$sTb{$symptomId}->{'symptomName'} // die;
        my $discarded   = %$sTb{$symptomId}->{'discarded'}   // die;
        $discarded      = unpack("N", pack("B32", substr("0" x 32 . $discarded, -32)));
        $symptoms{$symptomId}->{'symptomName'} = $symptomName;
        $symptoms{$symptomId}->{'discarded'}   = $discarded;
    }

    # Fetching confirmation target.
    my $confirmationTarget  = $self->param('confirmationTarget')  // die;
    my $operationsToPerform = $self->param('operationsToPerform') // die;
    my ($sqlParam, $sqlValue);
    if ($confirmationTarget eq 'pregancies') {
        $sqlParam = 'pregnancyConfirmationRequired';
        $sqlValue = 'pregnancyConfirmation';
    } else {
        die "something else to code";
    }
    my $rTb = $self->dbh->selectrow_hashref("
        SELECT
            id as reportId,
            vaersId,
            vaersVaccine,
            vaersSex,
            patientAge,
            creationTimestamp,
            aEDescription,
            vaersReceptionDate,
            vaccinationDate,
            pregnancyConfirmationRequired,
            pregnancyConfirmation,
            symptomsListed
        FROM vaers_fertility_report
        WHERE
            $sqlValue IS NULL AND
            $sqlParam = 1 AND
            (menstrualCycleDisordersConfirmation IS NULL OR menstrualCycleDisordersConfirmation != 1) AND
            (babyExposureConfirmation IS NULL OR babyExposureConfirmation != 1)
        LIMIT 1", undef);
    my $reportId                      = %$rTb{'reportId'};
    unless ($reportId) {
        $self->render(text => 'Done processing data. <div class="url-link noselect" onclick="openLocation(\'/studies/vaers_fertility\');return;">&#10229; Return to study</div>.')
    }
    my $vaersId                       = %$rTb{'vaersId'}                         // die;
    my $vaersVaccine                  = %$rTb{'vaersVaccine'}                    // die;
    my $vaersVaccineName              = $enums{'vaersVaccine'}->{$vaersVaccine} // die;
    my $vaersSex                      = %$rTb{'vaersSex'}                        // die;
    my $vaersSexName                  = $enums{'vaersSex'}->{$vaersSex}         // die;
    my $patientAge                    = %$rTb{'patientAge'};
    my $creationTimestamp             = %$rTb{'creationTimestamp'}               // die;
    my $creationDatetime              = time::timestamp_to_datetime($creationTimestamp);
    my $aEDescription                 = %$rTb{'aEDescription'}                   // die;
    my $vaersReceptionDate            = %$rTb{'vaersReceptionDate'}              // die;
    my $pregnancyConfirmationRequired = %$rTb{'pregnancyConfirmationRequired'}   // die;
    $pregnancyConfirmationRequired    = unpack("N", pack("B32", substr("0" x 32 . $pregnancyConfirmationRequired, -32)));
    my $vaccinationDate               = %$rTb{'vaccinationDate'};
    my $pregnancyConfirmation         = %$rTb{'pregnancyConfirmation'};
    if (!defined $pregnancyConfirmation && $pregnancyConfirmationRequired) {
        $aEDescription =~ s/pregnan/\<span style=\"background:yellow;\"\>pregnan\<\/span\>/g;
        $aEDescription =~ s/Pregnan/\<span style=\"background:yellow;\"\>Pregnan\<\/span\>/g;
        $aEDescription =~ s/PREGNAN/\<span style=\"background:yellow;\"\>PREGNAN\<\/span\>/g;
        $aEDescription =~ s/gestation/\<span style=\"background:yellow;\"\>gestation\<\/span\>/g;
        $aEDescription =~ s/Gestation/\<span style=\"background:yellow;\"\>Gestation\<\/span\>/g;
        $aEDescription =~ s/GESTATION/\<span style=\"background:yellow;\"\>GESTATION\<\/span\>/g;
        $aEDescription =~ s/estimated date of delivery/\<span style=\"background:yellow;\"\>estimated date of delivery\<\/span\>/g;
        $aEDescription =~ s/Estimated date of delivery/\<span style=\"background:yellow;\"\>Estimated date of delivery\<\/span\>/g;
        $aEDescription =~ s/ESTIMATED DATE OF DELIVERY/\<span style=\"background:yellow;\"\>ESTIMATED DATE OF DELIVERY\<\/span\>/g;
        $aEDescription =~ s/estimated due date/\<span style=\"background:yellow;\"\>estimated due date\<\/span\>/g;
        $aEDescription =~ s/Estimated due date/\<span style=\"background:yellow;\"\>Estimated due date\<\/span\>/g;
        $aEDescription =~ s/EDD/\<span style=\"background:yellow;\"\>EDD\<\/span\>/g;
        $aEDescription =~ s/DOD/\<span style=\"background:yellow;\"\>DOD\<\/span\>/g;
        $aEDescription =~ s/missed AB/\<span style=\"background:yellow;\"\>missed AB\<\/span\>/g;
        $aEDescription =~ s/miscarriage/\<span style=\"background:yellow;\"\>miscarriage\<\/span\>/g;
        $aEDescription =~ s/MISCARRIAGE/\<span style=\"background:yellow;\"\>MISCARRIAGE\<\/span\>/g;
    } else {
        die "something else to code";
    }
    my $symptomsListed                = %$rTb{'symptomsListed'}  // die;
    $symptomsListed                   = decode_json($symptomsListed);
    my $symptoms = '<div style="width:300px;margin:auto;"><ul>';
    for my $symptomId (@$symptomsListed) {
        my $symptomName = $symptoms{$symptomId}->{'symptomName'} // next;
        my $discarded   = $symptoms{$symptomId}->{'discarded'}   // die;
        if ($discarded) {
            $symptoms .= '<li><span style="background:darkred;">' . $symptomName . '</span></li>';
        } else {
            # Highlightig symptoms for pregnancies.
            if (
                $symptomName eq 'Exposure during pregnancy'          || $symptomName eq 'Maternal exposure during pregnancy'      || $symptomName eq 'Pregnancy' ||
                $symptomName eq 'Maternal exposure before pregnancy' || $symptomName eq 'Maternal exposure during breast feeding' || $symptomName eq 'Foetal heart rate abnormal' ||
                $symptomName eq 'Premature labour'                   || $symptomName eq 'Cleft lip'                               || $symptomName eq 'Maternal exposure timing unspecified' ||
                $symptomName eq 'Premature baby'                     || $symptomName eq 'Pregnancy test positive'                 || $symptomName eq 'Foetal disorder' ||
                $symptomName eq 'Foetal exposure during pregnancy'   || $symptomName eq 'Uterine dilation and curettage'          || $symptomName eq 'Cleft lip and palate' ||
                $symptomName eq 'Foetal cardiac arrest'              || $symptomName eq 'Pregnancy test positive'                 || $symptomName eq 'Stillbirth' ||
                $symptomName eq 'Foetal hypokinesia'                 || $symptomName eq 'Foetal non-stress test normal'           || $symptomName eq 'Abortion missed' ||
                $symptomName eq 'Labour induction'                   || $symptomName eq 'Amniotic fluid index decreased'          || $symptomName eq 'Ultrasound antenatal screen normal' ||
                $symptomName eq 'Hydrops foetalis'                   || $symptomName eq 'Premature delivery'                      || $symptomName eq 'Ultrasound foetal abnormal' ||
                $symptomName eq 'Caesarean section'                  || $symptomName eq 'Failed induction of labour'              || $symptomName eq 'Gestational hypertension' ||
                $symptomName eq 'Ultrasound foetal'                  || $symptomName eq 'Placental disorder'                      || $symptomName eq 'Ectopic pregnancy' ||
                $symptomName eq 'Foetal growth restriction'          || $symptomName eq 'Placental insufficiency'                 || $symptomName eq 'Foetal death' ||
                $symptomName eq 'Umbilical cord abnormality'         || $symptomName eq 'Amniocentesis'                           || $symptomName eq 'Ultrasound antenatal screen abnormal' ||
                $symptomName eq 'Umbilical cord around neck'         || $symptomName eq 'Ultrasound antenatal screen abnormal'    || $symptomName eq 'Complication of pregnancy' ||
                $symptomName eq 'Foetal chromosome abnormality'      || $symptomName eq 'Foetal cystic hygroma'                   || $symptomName eq 'Abortion' ||
                $symptomName eq 'Bradycardia foetal'                 || $symptomName eq 'Foetal monitoring'                       || $symptomName eq 'Foetal non-stress test' ||
                $symptomName eq 'Low birth weight baby'              || $symptomName eq 'Induced labour'                          || $symptomName eq 'Tachycardia foetal' ||
                $symptomName eq 'Amniotic cavity infection'          || $symptomName eq 'Premature rupture of membranes'          || $symptomName eq 'Abortion spontaneous' ||
                $symptomName eq 'Anembryonic gestation'              || $symptomName eq 'Abortion spontaneous complete'           || $symptomName eq 'First trimester pregnancy' ||
                $symptomName eq 'Abortion threatened'                || $symptomName eq 'Haemorrhage in pregnancy'                || $symptomName eq 'Uterine dilation and evacuation' ||
                $symptomName eq 'Premature separation of placenta'   || $symptomName eq 'Prenatal screening test'                 || $symptomName eq 'Foetal growth abnormality' ||
                $symptomName eq 'Foetal renal impairment'            || $symptomName eq 'Cerebral haemorrhage foetal'             || $symptomName eq 'Foetal placental thrombosis' ||
                $symptomName eq 'Human chorionic gonadotropin increased' || $symptomName eq 'Foetal cardiac disorder'
                
            ) {
                $symptoms .= '<li><span style="background:yellow;">' . $symptomName . '</span></li>';
            } elsif (
                $symptomName eq 'Intermenstrual bleeding'         || $symptomName eq 'Menstruation delayed'    || $symptomName eq 'Menstruation irregular'        ||
                $symptomName eq 'Vaginal haemorrhage'             || $symptomName eq 'Pregnancy test negative' || $symptomName eq 'Amenorrhoea'                   ||
                $symptomName eq 'Oligomenorrhoea'                 || $symptomName eq 'Oligomenorrhea'          || $symptomName eq 'Heavy menstrual bleeding'      ||
                $symptomName eq 'Menstrual disorder'              || $symptomName eq 'Haemorrhage'             || $symptomName eq 'Pelvic pain'                   ||
                $symptomName eq 'Ultrasound scan vagina abnormal' || $symptomName eq 'Dysmenorrhoea'           || $symptomName eq 'Polymenorrhoea'                ||
                $symptomName eq 'Breast swelling'                 || $symptomName eq 'Adnexa uteri pain'       || $symptomName eq 'Benign hydatidiform mole'      ||
                $symptomName eq 'Uterine haemorrhage'             || $symptomName eq 'Hysterectomy'            || $symptomName eq 'Fallopian tube operation'      ||
                $symptomName eq 'Breast cyst'                     || $symptomName eq 'Breast mass'             || $symptomName eq 'Polycystic ovaries'            ||
                $symptomName eq 'Infertility female'              || $symptomName eq 'Ovarian mass'            || $symptomName eq 'Ovarian granulosa cell tumour' ||
                $symptomName eq 'Amniorrhoea'                     || $symptomName eq 'Lactation disorder'      || $symptomName eq 'Ovulation disorder'
            ) {
                $symptoms .= '<li><span style="background:#f5d0f4;">' . $symptomName . '</span></li>';
            } else { # Symptoms are not of focus.
                $symptoms .= '<li><span>' . $symptomName . '</span></li>';
            }
        }
    }
    $symptoms .= '</ul></div>';



    $self->render(
        currentLanguage               => $currentLanguage,
        confirmationTarget            => $confirmationTarget,
        operationsToPerform           => $operationsToPerform,
        reportId                      => $reportId,
        vaersId                       => $vaersId,
        symptoms                      => $symptoms,
        vaersVaccine                  => $vaersVaccine,
        vaersVaccineName              => $vaersVaccineName,
        vaersReceptionDate            => $vaersReceptionDate,
        vaccinationDate               => $vaccinationDate,
        vaersSex                      => $vaersSex,
        vaersSexName                  => $vaersSexName,
        aEDescription                 => $aEDescription,
        patientAge                    => $patientAge,
        creationDatetime              => $creationDatetime,
        pregnancyConfirmation         => $pregnancyConfirmation,
        pregnancyConfirmationRequired => $pregnancyConfirmationRequired,
        sqlValue                      => $sqlValue,
        languages                     => \%languages
    );
}

sub set_report_pregnancy_attribute {
    my $self     = shift;

    my $reportId = $self->param('reportId') // die;
    my $sqlValue = $self->param('sqlValue') // die;
    my $value    = $self->param('value')    // die;

    my $sth      = $self->dbh->prepare("UPDATE vaers_fertility_report SET $sqlValue = $value, $sqlValue" . "Timestamp = UNIX_TIMESTAMP() WHERE id = $reportId");
    $sth->execute() or die $sth->err();

    $self->render(text => 'ok');
}

sub vaers_fertility {
    my $self = shift;

    # Loggin session if unknown.
    session::session_from_self($self);

    # Setting language & lang options.
    my %config          = %{$self->config()};
    my $environment     = $config{'environment'} // die;
    my $currentLanguage = $self->param('currentLanguage') // 'fr';
    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    # Fetching VAERS statistics.
    my %vaersStatistics = ();
    my $cCottonStatsFile = 'stats/vaers_fertility_study.json';
    if (-f $cCottonStatsFile) {
        my $json;
        open my $in, '<:utf8', $cCottonStatsFile;
        while (<$in>) {
            $json .= $_;
        }
        close $in;
        $json = decode_json($json);
        %vaersStatistics = %$json;
    }
    # p%vaersStatistics;

    $self->render(
        environment => $environment,
        currentLanguage => $currentLanguage,
        languages       => \%languages,
        vaersStatistics => \%vaersStatistics
    );
}

sub pregnancies_arbitrations {
    my $self = shift;
    my $currentLanguage = $self->param('currentLanguage') // 'fr';
    my %config          = %{$self->config()};
    my $environment     = $config{'environment'} // die;

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    $self->render(
        environment     => $environment,
        currentLanguage => $currentLanguage,
        languages       => \%languages,
    );
}

sub load_pregnancies_arbitrations_filters {
    my $self = shift;

    my %enums = %{$self->enums()};
    # p%enums;
    my %forms = ();
    for my $vaersSex (sort keys %{$enums{'vaersSex'}}) {
        my $vaersSexName = $enums{'vaersSex'}->{$vaersSex} // die;
        $forms{'vaersSex'}->{$vaersSexName} = $vaersSex;
    }
    for my $vaersVaccine (sort keys %{$enums{'vaersVaccine'}}) {
        my $vaersVaccineName = $enums{'vaersVaccine'}->{$vaersVaccine} // die;
        $forms{'vaersVaccine'}->{$vaersVaccine} = $vaersVaccineName;
    }

    # Listing sexes stored.
    my $cSxTb = $self->dbh->selectall_hashref("SELECT id as cdcSexId, name as cdcSexName FROM cdc_sexe", 'cdcSexId');
    for my $cdcSexId (sort{$a <=> $b} keys %$cSxTb) {
        my $cdcSexName = %$cSxTb{$cdcSexId}->{'cdcSexName'} // die;
        $forms{'cdcSex'}->{$cdcSexId} = $cdcSexName;
    }

    # Listing states stored.
    my $cSTb = $self->dbh->selectall_hashref("SELECT id as cdcStateId, name as cdcStateName FROM cdc_state", 'cdcStateId');
    for my $cdcStateId (sort{$a <=> $b} keys %$cSTb) {
        my $cdcStateName = %$cSTb{$cdcStateId}->{'cdcStateName'} // die;
        $forms{'cdcState'}->{$cdcStateName}->{'cdcStateId'} = $cdcStateId;
    }

    # Listing manufacturers stored.
    my $cMTb = $self->dbh->selectall_hashref("SELECT id as cdcManufacturerId, name as cdcManufacturerName FROM cdc_manufacturer", 'cdcManufacturerId');
    for my $cdcManufacturerId (sort{$a <=> $b} keys %$cMTb) {
        my $cdcManufacturerName = %$cMTb{$cdcManufacturerId}->{'cdcManufacturerName'} // die;
        $forms{'cdcManufacturer'}->{$cdcManufacturerName}->{'cdcManufacturerId'} = $cdcManufacturerId;
    }

    # Listing vaccine types stored.
    my $cVTTb = $self->dbh->selectall_hashref("SELECT id as cdcVaccineTypeId, name as cdcVaccineTypeName FROM cdc_vaccine_type", 'cdcVaccineTypeId');
    for my $cdcVaccineTypeId (sort{$a <=> $b} keys %$cVTTb) {
        my $cdcVaccineTypeName = %$cVTTb{$cdcVaccineTypeId}->{'cdcVaccineTypeName'} // die;
        $forms{'cdcVaccineType'}->{$cdcVaccineTypeName}->{'cdcVaccineTypeId'} = $cdcVaccineTypeId;
    }

    # Listing vaccine stored.
    my $cVTb = $self->dbh->selectall_hashref("SELECT id as cdcVaccineId, name as cdcVaccineName FROM cdc_vaccine", 'cdcVaccineId');
    for my $cdcVaccineId (sort{$a <=> $b} keys %$cVTb) {
        my $cdcVaccineName = %$cVTb{$cdcVaccineId}->{'cdcVaccineName'} // die;
        $forms{'cdcVaccine'}->{$cdcVaccineName}->{'cdcVaccineId'} = $cdcVaccineId;
    }

    # Listing symptoms stored.
    my $eRTb = $self->dbh->selectall_hashref("SELECT id as cdcSymptomId, name as cdcSymptomName FROM cdc_symptom", 'cdcSymptomId');
    for my $cdcSymptomId (sort{$a <=> $b} keys %$eRTb) {
        my $cdcSymptomName = %$eRTb{$cdcSymptomId}->{'cdcSymptomName'} // die;
        $forms{'cdcSymptom'}->{$cdcSymptomName}->{'cdcSymptomId'} = $cdcSymptomId;
    }

    $self->render(
        forms => \%forms
    );
}

sub load_pregnancies_arbitrations_reports {
    my $self                = shift;
    my $pageNumber          = $self->param('pageNumber') // die;
    my $cdcStateId          = $self->param('cdcStateId');
    my $cdcSex              = $self->param('cdcSex');
    my $fromAge             = $self->param('fromAge');
    my $toAge               = $self->param('toAge');
    my $noticeSearch        = $self->param('noticeSearch');
    my $permanentDisability = $self->param('permanentDisability');
    my $lifeThreatning      = $self->param('lifeThreatning');
    my $hospitalized        = $self->param('hospitalized');
    my $cdcVaccineTypeId    = $self->param('cdcVaccineTypeId');
    my $patientDied         = $self->param('patientDied');
    my $cdcVaccineId        = $self->param('cdcVaccineId');
    my $cdcSymptomId        = $self->param('cdcSymptomId');
    my $cdcManufacturerId   = $self->param('cdcManufacturerId');
    my $covidVaccinesOnly   = $self->param('covidVaccinesOnly');
    my %enums               = %{$self->enums()};
    say "pageNumber          : $pageNumber";
    say "cdcStateId          : $cdcStateId";
    say "cdcSex              : $cdcSex";
    say "fromAge             : $fromAge";
    say "toAge               : $toAge";
    say "noticeSearch        : $noticeSearch";
    say "permanentDisability : $permanentDisability";
    say "lifeThreatning      : $lifeThreatning";
    say "cdcVaccineTypeId    : $cdcVaccineTypeId";
    say "patientDied         : $patientDied";
    say "cdcVaccineId        : $cdcVaccineId";
    say "cdcSymptomId        : $cdcSymptomId";
    say "cdcManufacturerId   : $cdcManufacturerId";
    say "covidVaccinesOnly   : $covidVaccinesOnly";

    # Fetching symptoms.
    my %cdcSymptoms = ();
    my $cSTb = $self->dbh->selectall_hashref("SELECT id as cdcSymptomId, name as cdcSymptomName FROM cdc_symptom", 'cdcSymptomId');
    for my $cdcSymptomId (sort{$a <=> $b} keys %$cSTb) {
        my $cdcSymptomName = %$cSTb{$cdcSymptomId}->{'cdcSymptomName'} // die;
        $cdcSymptoms{$cdcSymptomId}->{'cdcSymptomName'} = $cdcSymptomName;
    }

    # Fetching vaccines.
    my %cdcVaccines = ();
    my $cVTb = $self->dbh->selectall_hashref("
        SELECT
            cdc_vaccine.id as cdcVaccineId,
            cdc_vaccine.cdcVaccineTypeId,
            cdc_vaccine_type.name as cdcVaccineTypeName,
            cdc_vaccine.cdcManufacturerId,
            cdc_vaccine.cdcVaccineTypeId,
            cdc_manufacturer.name as cdcManufacturerName,
            cdc_vaccine.name as cdcVaccineName
        FROM cdc_vaccine
            LEFT JOIN cdc_manufacturer ON cdc_manufacturer.id = cdc_vaccine.cdcManufacturerId
            LEFT JOIN cdc_vaccine_type ON cdc_vaccine_type.id = cdc_vaccine.cdcVaccineTypeId
        ", 'cdcVaccineId');
    for my $cdcVaccineId (sort{$a <=> $b} keys %$cVTb) {
        my $cdcManufacturerId   = %$cVTb{$cdcVaccineId}->{'cdcManufacturerId'}   // die;
        my $cdcManufacturerName = %$cVTb{$cdcVaccineId}->{'cdcManufacturerName'} // die;
        my $cdcVaccineTypeId    = %$cVTb{$cdcVaccineId}->{'cdcVaccineTypeId'}    // die;
        my $cdcVaccineTypeName  = %$cVTb{$cdcVaccineId}->{'cdcVaccineTypeName'}  // die;
        my $cdcVaccineName      = %$cVTb{$cdcVaccineId}->{'cdcVaccineName'}      // die;
        $cdcVaccines{$cdcVaccineId}->{'cdcManufacturerId'}   = $cdcManufacturerId;
        $cdcVaccines{$cdcVaccineId}->{'cdcManufacturerName'} = $cdcManufacturerName;
        $cdcVaccines{$cdcVaccineId}->{'cdcVaccineTypeId'}    = $cdcVaccineTypeId;
        $cdcVaccines{$cdcVaccineId}->{'cdcVaccineTypeName'}  = $cdcVaccineTypeName;
        $cdcVaccines{$cdcVaccineId}->{'cdcVaccineName'}      = $cdcVaccineName;
    }

    # Fetching notices.
    my @cdcReports             = ();
    my $sql                    = "
        SELECT
            cdc_report.id as cdcReportId,
            cdcStateId,
            cdc_state.name as cdcStateName,
            cdc_report.internalId,
            vaccinationDate,
            cdcReceptionDate,
            cdcSexeId as cdcSex,
            cdc_sexe.name as cdcSexName,
            cdcVaccineAdministrator,
            patientAge,
            aEDescription,
            patientDied,
            lifeThreatning,
            hospitalized,
            permanentDisability,
            parsingTimestamp
        FROM cdc_report
            LEFT JOIN cdc_state ON cdc_state.id = cdc_report.cdcStateId
            LEFT JOIN cdc_sexe ON cdc_sexe.id = cdc_report.cdcSexeId
        WHERE
            cdc_report.id IS NOT NULL";
    if ($cdcStateId) {
        $sql .= " AND cdcStateId = $cdcStateId";
    }
    if ($cdcSex) {
        $sql .= " AND cdcSexeId = $cdcSex";
    }
    if ($fromAge) {
        $sql .= " AND patientAge >= $fromAge";
    }
    if ($toAge) {
        $sql .= " AND patientAge <= $toAge";
    }
    if ($patientDied) {
        $sql .= " AND cdc_report.patientDied = 1" if $patientDied == 1;
        $sql .= " AND cdc_report.patientDied = 0" if $patientDied == 2;
    }
    if ($lifeThreatning) {
        $sql .= " AND cdc_report.lifeThreatning = 1" if $lifeThreatning == 1;
        $sql .= " AND cdc_report.lifeThreatning = 0" if $lifeThreatning == 2;
    }
    if ($hospitalized) {
        $sql .= " AND cdc_report.hospitalized = 1" if $hospitalized == 1;
        $sql .= " AND cdc_report.hospitalized = 0" if $hospitalized == 2;
    }
    if ($permanentDisability) {
        $sql .= " AND cdc_report.permanentDisability = 1" if $permanentDisability == 1;
        $sql .= " AND cdc_report.permanentDisability = 0" if $permanentDisability == 2;
    }
    say $sql;
    my $tb        = $self->dbh->selectall_hashref($sql, 'cdcReportId');
    my $toEntry   = $pageNumber * 50;
    my $fromEntry = $toEntry - 49;
    say "from : $fromEntry -> to : $toEntry";
    my $totalEcdcReports = 0;
    for my $cdcReportId (sort{$a <=> $b} keys %$tb) {
        $totalEcdcReports++;
        if ($totalEcdcReports >= $fromEntry && $totalEcdcReports <= $toEntry) {
            # Filtering by vaccine, type or manufacturer if required.
            if ($cdcVaccineTypeId || $cdcManufacturerId || $cdcVaccineId) {
                my $hasVaccineType = 0;
                my $hasVaccine     = 0;
                my $cRVTb = $self->dbh->selectall_hashref("SELECT cdcVaccineId, dose FROM cdc_report_vaccine WHERE cdcReportId = $cdcReportId", 'cdcVaccineId') or die $!;
                next unless keys %$cRVTb;
                for my $cVId (sort{$a <=> $b} keys %$cRVTb) {
                    my $cdcVaccineName      = $cdcVaccines{$cVId}->{'cdcVaccineName'}      // die;
                    my $cMId                = $cdcVaccines{$cVId}->{'cdcManufacturerId'}   // die;
                    my $cdcManufacturerName = $cdcVaccines{$cVId}->{'cdcManufacturerName'} // die;
                    my $cVTId               = $cdcVaccines{$cVId}->{'cdcVaccineTypeId'}    // die;
                    my $cdcVaccineTypeName  = $cdcVaccines{$cVId}->{'cdcVaccineTypeName'}  // die;
                    if ($cdcVaccineTypeId) {
                        $hasVaccineType = 1 if $cdcVaccineTypeId == $cVTId;
                    }
                    if ($cdcVaccineId) {
                        $hasVaccine = 1 if $cdcVaccineId == $cVId;
                    }

                }
                if ($cdcVaccineTypeId) {
                    unless ($hasVaccineType == 1) {
                        $totalEcdcReports--;
                        next;
                    }
                }
                if ($cdcVaccineId) {
                    unless ($hasVaccine == 1) {
                        $totalEcdcReports--;
                        next;
                    }
                }
            }
            # Filtering by symptom if required.
            if ($cdcSymptomId) {
                my $hasSymptom = 0;
                my $cRSTb = $self->dbh->selectall_hashref("SELECT cdcSymptomId FROM cdc_report_symptom WHERE cdcReportId = $cdcReportId", 'cdcSymptomId') or die $!;
                next unless keys %$cRSTb;
                for my $cSId (sort{$a <=> $b} keys %$cRSTb) {
                    $hasSymptom = 1 if $cdcSymptomId == $cSId;
                }
                if ($cdcSymptomId) {
                    unless ($hasSymptom == 1) {
                        $totalEcdcReports--;
                        next;
                    }
                }
            }
            my $cdcStateId                   = %$tb{$cdcReportId}->{'cdcStateId'}          // die;
            my $cdcStateName                 = %$tb{$cdcReportId}->{'cdcStateName'}        // die;
            my $internalId                   = %$tb{$cdcReportId}->{'internalId'}          // die;
            my $vaccinationDate              = %$tb{$cdcReportId}->{'vaccinationDate'};
            my $cdcReceptionDate             = %$tb{$cdcReportId}->{'cdcReceptionDate'};
            my $cdcSex                       = %$tb{$cdcReportId}->{'cdcSex'}              // die;
            my $cdcSexName                   = %$tb{$cdcReportId}->{'cdcSexName'}          // die;
            my $patientAge                   = %$tb{$cdcReportId}->{'patientAge'};
            my $aEDescription                = %$tb{$cdcReportId}->{'aEDescription'};
            my $patientDied                  = %$tb{$cdcReportId}->{'patientDied'}         // die;
            my $lifeThreatning               = %$tb{$cdcReportId}->{'lifeThreatning'}      // die;
            my $hospitalized                 = %$tb{$cdcReportId}->{'hospitalized'}        // die;
            my $permanentDisability          = %$tb{$cdcReportId}->{'permanentDisability'} // die;
            $patientDied                     = unpack("N", pack("B32", substr("0" x 32 . $patientDied, -32)));
            $lifeThreatning                  = unpack("N", pack("B32", substr("0" x 32 . $lifeThreatning, -32)));
            $hospitalized                    = unpack("N", pack("B32", substr("0" x 32 . $hospitalized, -32)));
            $permanentDisability             = unpack("N", pack("B32", substr("0" x 32 . $permanentDisability, -32)));
            if ($patientDied == 1) {
                $patientDied = 'Yes';
            } elsif ($patientDied == 0) {
                $patientDied = 'No';
            } else {
                die "patientDied : $patientDied";
            }
            if ($lifeThreatning == 1) {
                $lifeThreatning = 'Yes';
            } elsif ($lifeThreatning == 0) {
                $lifeThreatning = 'No';
            } else {
                die "lifeThreatning : $lifeThreatning";
            }
            if ($hospitalized == 1) {
                $hospitalized = 'Yes';
            } elsif ($hospitalized == 0) {
                $hospitalized = 'No';
            } else {
                die "hospitalized : $hospitalized";
            }
            if ($permanentDisability == 1) {
                $permanentDisability = 'Yes';
            } elsif ($permanentDisability == 0) {
                $permanentDisability = 'No';
            } else {
                die "permanentDisability : $permanentDisability";
            }
            my %obj = ();
            $obj{'cdcStateId'}               = $cdcStateId;
            $obj{'cdcStateName'}             = $cdcStateName;
            $obj{'internalId'}               = "$internalId-1";
            $obj{'vaccinationDate'}          = $vaccinationDate;
            $obj{'cdcReceptionDate'}         = $cdcReceptionDate;
            $obj{'cdcSex'}                   = $cdcSex;
            $obj{'aEDescription'}            = $aEDescription;
            $obj{'cdcSexName'}               = $cdcSexName;
            $obj{'patientAge'}               = $patientAge;
            $obj{'patientDied'}              = $patientDied;
            $obj{'lifeThreatning'}           = $lifeThreatning;
            $obj{'hospitalized'}             = $hospitalized;
            $obj{'permanentDisability'}      = $permanentDisability;

            # Integrating symptoms related to the report.
            my $cRSTb = $self->dbh->selectall_hashref("SELECT cdcSymptomId FROM cdc_report_symptom WHERE cdcReportId = $cdcReportId", 'cdcSymptomId') or die $!;
            for my $cSId (sort{$a <=> $b} keys %$cRSTb) {
                my $cdcSymptomName = $cdcSymptoms{$cSId}->{'cdcSymptomName'} // die;
                my %o = ();
                $o{'cdcSymptomId'}   = $cSId;
                $o{'cdcSymptomName'} = $cdcSymptomName;
                push @{$obj{'symptoms'}}, \%o;
            }

            # Integrating vaccines details.
            my $cRVTb = $self->dbh->selectall_hashref("SELECT cdcVaccineId, dose FROM cdc_report_vaccine WHERE cdcReportId = $cdcReportId", 'cdcVaccineId') or die $!;
            for my $cVId (sort{$a <=> $b} keys %$cRVTb) {
                my $cdcVaccineName      = $cdcVaccines{$cVId}->{'cdcVaccineName'}      // die;
                my $cMId                = $cdcVaccines{$cVId}->{'cdcManufacturerId'}   // die;
                my $cdcManufacturerName = $cdcVaccines{$cVId}->{'cdcManufacturerName'} // die;
                my $cVTId               = $cdcVaccines{$cVId}->{'cdcVaccineTypeId'}    // die;
                my $cdcVaccineTypeName  = $cdcVaccines{$cVId}->{'cdcVaccineTypeName'}  // die;
                my $dose                = %$cRVTb{$cVId}->{'dose'}                     // '';
                my %o                   = ();
                $o{'cdcVaccineId'}      = $cVId;
                $o{'cdcVaccineName'}    = $cdcVaccineName;
                push @{$obj{'vaccines'}}, \%o;
                my %o2                     = ();
                $o2{'cdcManufacturerId'}   = $cMId;
                $o2{'cdcManufacturerName'} = $cdcManufacturerName;
                push @{$obj{'vaccineManufacturers'}}, \%o2;
                my %o3                     = ();
                $o3{'cdcVaccineTypeId'}    = $cVTId;
                $o3{'cdcVaccineTypeName'}  = $cdcVaccineTypeName;
                push @{$obj{'vaccineTypes'}}, \%o3;
                my %o4                     = ();
                $o4{'dose'}                = $dose;
                push @{$obj{'doses'}}, \%o4;
            }

            push @cdcReports, \%obj;
        }
    }
    my ($maxPages, %pages) = data_formatting::paginate($pageNumber, $totalEcdcReports, 50);
    # p%pages;
    # p@cdcReports;

    $self->render(
        pageNumber       => $pageNumber,
        maxPages         => $maxPages,
        totalEcdcReports => $totalEcdcReports,
        noticeSearch     => $noticeSearch,
        cdcReports      => \@cdcReports,
        pages            => \%pages
    );
}

sub pregnancies_seriousness {
    my $self = shift;

    # Loggin session if unknown.
    session::session_from_self($self);

    # Setting language & lang options.
    my $currentLanguage = $self->param('currentLanguage') // 'fr';
    my %languages       = ();
    $languages{'fr'}    = 'French';
    $languages{'en'}    = 'English';
    my %config          = %{$self->config()};
    my $environment     = $config{'environment'} // die;

    # Fetching total operations to perform.
    my $tb = $self->dbh->selectrow_hashref("SELECT count(id) as operationsToPerform FROM vaers_fertility_report WHERE seriousnessConfirmation IS NULL AND seriousnessConfirmationRequired = 1", undef);
    my $operationsToPerform = %$tb{'operationsToPerform'} // die;

    $self->render(
        currentLanguage     => $currentLanguage,
        operationsToPerform => $operationsToPerform,
        environment         => $environment,
        languages           => \%languages
    );
}

sub load_pregnancy_seriousness_confirmation {
    my $self = shift;

    # Loggin session if unknown.
    session::session_from_self($self);
    my %enums = %{$self->enums()};

    # Setting language & lang options.
    my $currentLanguage = $self->param('currentLanguage') // 'fr';
    my %languages       = ();
    $languages{'fr'}    = 'French';
    $languages{'en'}    = 'English';
    my %config          = %{$self->config()};
    my $environment     = $config{'environment'} // die;
    if ($environment ne "local") {
        $self->render(text => 'Disallowed');
    }

    # Fetching vaers symptoms.
    my %symptoms = ();
    my $sTb = $self->dbh->selectall_hashref("SELECT id as symptomId, name as symptomName, discarded FROM vaers_fertility_symptom", 'symptomId');
    for my $symptomId (sort{$a <=> $b} keys %$sTb) {
        my $symptomName = %$sTb{$symptomId}->{'symptomName'} // die;
        my $discarded   = %$sTb{$symptomId}->{'discarded'}   // die;
        $discarded      = unpack("N", pack("B32", substr("0" x 32 . $discarded, -32)));
        $symptoms{$symptomId}->{'symptomName'} = $symptomName;
        $symptoms{$symptomId}->{'discarded'}   = $discarded;
    }

    # Fetching confirmation target.
    my $operationsToPerform = $self->param('operationsToPerform') // die;
    my $sqlParam            = 'seriousnessConfirmationRequired';
    my $sqlValue            = 'seriousnessConfirmation';
    my $rTb                 = $self->dbh->selectrow_hashref("
        SELECT
            id as reportId,
            vaersId,
            vaersVaccine,
            vaersSex,
            patientAge,
            creationTimestamp,
            aEDescription,
            vaersReceptionDate,
            onsetDate,
            vaccinationDate,
            seriousnessConfirmationRequired,
            seriousnessConfirmation,
            childDied,
            childSeriousAE,
            hospitalized,
            permanentDisability,
            lifeThreatning,
            patientDied,
            symptomsListed
        FROM vaers_fertility_report
        WHERE
            $sqlValue IS NULL AND
            $sqlParam = 1 ORDER BY RAND()
        LIMIT 1", undef);
    my $reportId                        = %$rTb{'reportId'}                        // die;
    my $vaersId                         = %$rTb{'vaersId'}                         // die;
    my $vaersVaccine                    = %$rTb{'vaersVaccine'}                    // die;
    my $vaersVaccineName                = $enums{'vaersVaccine'}->{$vaersVaccine} // die;
    my $vaersSex                        = %$rTb{'vaersSex'}                        // die;
    my $vaersSexName                    = $enums{'vaersSex'}->{$vaersSex}         // die;
    my $patientAge                      = %$rTb{'patientAge'};
    my $creationTimestamp               = %$rTb{'creationTimestamp'}               // die;
    my $creationDatetime                = time::timestamp_to_datetime($creationTimestamp);
    my $aEDescription                   = %$rTb{'aEDescription'}                   // die;
    my $vaersReceptionDate              = %$rTb{'vaersReceptionDate'}              // die;
    my $seriousnessConfirmationRequired = %$rTb{'seriousnessConfirmationRequired'}   // die;
    $seriousnessConfirmationRequired    = unpack("N", pack("B32", substr("0" x 32 . $seriousnessConfirmationRequired, -32)));
    my $hospitalized                    = %$rTb{'hospitalized'}        // die;
    $hospitalized                       = unpack("N", pack("B32", substr("0" x 32 . $hospitalized, -32)));
    my $permanentDisability             = %$rTb{'permanentDisability'} // die;
    $permanentDisability                = unpack("N", pack("B32", substr("0" x 32 . $permanentDisability, -32)));
    my $lifeThreatning                  = %$rTb{'lifeThreatning'}      // die;
    $lifeThreatning                     = unpack("N", pack("B32", substr("0" x 32 . $lifeThreatning, -32)));
    my $patientDied                     = %$rTb{'patientDied'}         // die;
    $patientDied                        = unpack("N", pack("B32", substr("0" x 32 . $patientDied, -32)));
    my $childDied                       = %$rTb{'childDied'}           // die;
    $childDied                          = unpack("N", pack("B32", substr("0" x 32 . $childDied, -32)));
    my $childSeriousAE                  = %$rTb{'childSeriousAE'}      // die;
    $childSeriousAE                     = unpack("N", pack("B32", substr("0" x 32 . $childSeriousAE, -32)));
    my $vaccinationDate                 = %$rTb{'vaccinationDate'};
    my $onsetDate                       = %$rTb{'onsetDate'};
    my $seriousnessConfirmation         = %$rTb{'seriousnessConfirmation'};
    if (!defined $seriousnessConfirmation && $seriousnessConfirmationRequired) {
        $aEDescription =~ s/pregnan/\<span style=\"background:yellow;\"\>pregnan\<\/span\>/g;
        $aEDescription =~ s/Pregnan/\<span style=\"background:yellow;\"\>Pregnan\<\/span\>/g;
        $aEDescription =~ s/PREGNAN/\<span style=\"background:yellow;\"\>PREGNAN\<\/span\>/g;
        $aEDescription =~ s/missed pregn/\<span style=\"background:yellow;\"\>missed pregn\<\/span\>/g;
        $aEDescription =~ s/abort/\<span style=\"background:yellow;\"\>abort\<\/span\>/g;
        $aEDescription =~ s/Abort/\<span style=\"background:yellow;\"\>Abort\<\/span\>/g;
        $aEDescription =~ s/ABORT/\<span style=\"background:yellow;\"\>ABORT\<\/span\>/g;
        $aEDescription =~ s/hospital/\<span style=\"background:yellow;\"\>hospital\<\/span\>/g;
        $aEDescription =~ s/Hospital/\<span style=\"background:yellow;\"\>Hospital\<\/span\>/g;
        $aEDescription =~ s/HOSPITAL/\<span style=\"background:yellow;\"\>HOSPITAL\<\/span\>/g;
        $aEDescription =~ s/ER/\<span style=\"background:yellow;\"\>ER\<\/span\>/g;
        $aEDescription =~ s/gravida/\<span style=\"background:yellow;\"\>gravida\<\/span\>/g;
        $aEDescription =~ s/Gravida/\<span style=\"background:yellow;\"\>Gravida\<\/span\>/g;
        $aEDescription =~ s/GRAVIDA/\<span style=\"background:yellow;\"\>GRAVIDA\<\/span\>/g;
        $aEDescription =~ s/emergency/\<span style=\"background:yellow;\"\>emergency\<\/span\>/g;
        $aEDescription =~ s/Emergency/\<span style=\"background:yellow;\"\>Emergency\<\/span\>/g;
        $aEDescription =~ s/EMERGENCY/\<span style=\"background:yellow;\"\>EMERGENCY\<\/span\>/g;
        $aEDescription =~ s/serious/\<span style=\"background:yellow;\"\>serious\<\/span\>/g;
        $aEDescription =~ s/Serious/\<span style=\"background:yellow;\"\>Serious\<\/span\>/g;
        $aEDescription =~ s/SERIOUS/\<span style=\"background:yellow;\"\>SERIOUS\<\/span\>/g;
        $aEDescription =~ s/had resolved/\<span style=\"background:yellow;\"\>had resolved\<\/span\>/g;
        $aEDescription =~ s/Had resolved/\<span style=\"background:yellow;\"\>Had resolved\<\/span\>/g;
        $aEDescription =~ s/Had Resolved/\<span style=\"background:yellow;\"\>Had Resolved\<\/span\>/g;
        $aEDescription =~ s/HAD RESOLVED/\<span style=\"background:yellow;\"\>HAD RESOLVED\<\/span\>/g;
        $aEDescription =~ s/miscarr/\<span style=\"background:yellow;\"\>miscarr\<\/span\>/g;
        $aEDescription =~ s/Miscarr/\<span style=\"background:yellow;\"\>Miscarr\<\/span\>/g;
        $aEDescription =~ s/MISCARR/\<span style=\"background:yellow;\"\>MISCARR\<\/span\>/g;
        $aEDescription =~ s/abortion/\<span style=\"background:yellow;\"\>abortion\<\/span\>/g;
        $aEDescription =~ s/Abortion/\<span style=\"background:yellow;\"\>Abortion\<\/span\>/g;
        $aEDescription =~ s/ABORTION/\<span style=\"background:yellow;\"\>ABORTION\<\/span\>/g;
        $aEDescription =~ s/premature/\<span style=\"background:yellow;\"\>premature\<\/span\>/g;
        $aEDescription =~ s/Premature/\<span style=\"background:yellow;\"\>Premature\<\/span\>/g;
        $aEDescription =~ s/PREMATURE/\<span style=\"background:yellow;\"\>PREMATURE\<\/span\>/g;
        $aEDescription =~ s/foetal/\<span style=\"background:yellow;\"\>foetal\<\/span\>/g;
        $aEDescription =~ s/Foetal/\<span style=\"background:yellow;\"\>Foetal\<\/span\>/g;
        $aEDescription =~ s/FOETAL/\<span style=\"background:yellow;\"\>FOETAL\<\/span\>/g;
        $aEDescription =~ s/bleed/\<span style=\"background:yellow;\"\>bleed\<\/span\>/g;
        $aEDescription =~ s/Bleed/\<span style=\"background:yellow;\"\>Bleed\<\/span\>/g;
        $aEDescription =~ s/BLEED/\<span style=\"background:yellow;\"\>BLEED\<\/span\>/g;
        $aEDescription =~ s/gestation/\<span style=\"background:yellow;\"\>gestation\<\/span\>/g;
        $aEDescription =~ s/Gestation/\<span style=\"background:yellow;\"\>Gestation\<\/span\>/g;
        $aEDescription =~ s/GESTATION/\<span style=\"background:yellow;\"\>GESTATION\<\/span\>/g;
        $aEDescription =~ s/estimated date of delivery/\<span style=\"background:yellow;\"\>estimated date of delivery\<\/span\>/g;
        $aEDescription =~ s/Estimated date of delivery/\<span style=\"background:yellow;\"\>Estimated date of delivery\<\/span\>/g;
        $aEDescription =~ s/ESTIMATED DATE OF DELIVERY/\<span style=\"background:yellow;\"\>ESTIMATED DATE OF DELIVERY\<\/span\>/g;
        $aEDescription =~ s/estimated due date/\<span style=\"background:yellow;\"\>estimated due date\<\/span\>/g;
        $aEDescription =~ s/Estimated due date/\<span style=\"background:yellow;\"\>Estimated due date\<\/span\>/g;
        $aEDescription =~ s/EDD/\<span style=\"background:yellow;\"\>EDD\<\/span\>/g;
    } else {
        die "something else to code";
    }
    my $symptomsListed                = %$rTb{'symptomsListed'}  // die;
    $symptomsListed                   = decode_json($symptomsListed);
    my $symptoms = '<div style="width:300px;margin:auto;"><ul>';
    for my $symptomId (@$symptomsListed) {
        my $symptomName = $symptoms{$symptomId}->{'symptomName'} // die;
        my $discarded   = $symptoms{$symptomId}->{'discarded'}   // die;
        if ($discarded) {
            $symptoms .= '<li><span style="background:darkred;">' . $symptomName . '</span></li>';
        } else {
            # Highlightig symptoms for pregnancies.
            if (
                $symptomName eq 'Exposure during pregnancy'          || $symptomName eq 'Maternal exposure during pregnancy'      || $symptomName eq 'Pregnancy' ||
                $symptomName eq 'Maternal exposure before pregnancy' || $symptomName eq 'Maternal exposure during breast feeding' || $symptomName eq 'Foetal heart rate abnormal' ||
                $symptomName eq 'Premature labour'                   || $symptomName eq 'Cleft lip'                               || $symptomName eq 'Maternal exposure timing unspecified' ||
                $symptomName eq 'Premature baby'                     || $symptomName eq 'Pregnancy test positive'                 || $symptomName eq 'Foetal disorder' ||
                $symptomName eq 'Foetal exposure during pregnancy'   || $symptomName eq 'Uterine dilation and curettage'          || $symptomName eq 'Cleft lip and palate' ||
                $symptomName eq 'Foetal cardiac arrest'              || $symptomName eq 'Pregnancy test positive'                 || $symptomName eq 'Stillbirth' ||
                $symptomName eq 'Foetal hypokinesia'                 || $symptomName eq 'Foetal non-stress test normal'           || $symptomName eq 'Abortion missed' ||
                $symptomName eq 'Labour induction'                   || $symptomName eq 'Amniotic fluid index decreased'          || $symptomName eq 'Ultrasound antenatal screen normal' ||
                $symptomName eq 'Hydrops foetalis'                   || $symptomName eq 'Premature delivery'                      || $symptomName eq 'Ultrasound foetal abnormal' ||
                $symptomName eq 'Caesarean section'                  || $symptomName eq 'Failed induction of labour'              || $symptomName eq 'Gestational hypertension' ||
                $symptomName eq 'Ultrasound foetal'                  || $symptomName eq 'Placental disorder'                      || $symptomName eq 'Ectopic pregnancy' ||
                $symptomName eq 'Foetal growth restriction'          || $symptomName eq 'Placental insufficiency'                 || $symptomName eq 'Foetal death' ||
                $symptomName eq 'Umbilical cord abnormality'         || $symptomName eq 'Amniocentesis'                           || $symptomName eq 'Ultrasound antenatal screen abnormal' ||
                $symptomName eq 'Umbilical cord around neck'         || $symptomName eq 'Ultrasound antenatal screen abnormal'    || $symptomName eq 'Complication of pregnancy' ||
                $symptomName eq 'Foetal chromosome abnormality'      || $symptomName eq 'Foetal cystic hygroma'                   || $symptomName eq 'Abortion' ||
                $symptomName eq 'Bradycardia foetal'                 || $symptomName eq 'Foetal monitoring'                       || $symptomName eq 'Foetal non-stress test' ||
                $symptomName eq 'Low birth weight baby'              || $symptomName eq 'Induced labour'                          || $symptomName eq 'Tachycardia foetal' ||
                $symptomName eq 'Amniotic cavity infection'          || $symptomName eq 'Premature rupture of membranes'          || $symptomName eq 'Abortion spontaneous' ||
                $symptomName eq 'Anembryonic gestation'              || $symptomName eq 'Abortion spontaneous complete'           || $symptomName eq 'First trimester pregnancy' ||
                $symptomName eq 'Abortion threatened'                || $symptomName eq 'Haemorrhage in pregnancy'                || $symptomName eq 'Uterine dilation and evacuation' ||
                $symptomName eq 'Premature separation of placenta'   || $symptomName eq 'Prenatal screening test'                 || $symptomName eq 'Foetal growth abnormality' ||
                $symptomName eq 'Foetal renal impairment'
                
            ) {
                $symptoms .= '<li><span style="background:yellow;">' . $symptomName . '</span></li>';
            } elsif (
                $symptomName eq 'Intermenstrual bleeding'         || $symptomName eq 'Menstruation delayed'    || $symptomName eq 'Menstruation irregular'        ||
                $symptomName eq 'Vaginal haemorrhage'             || $symptomName eq 'Pregnancy test negative' || $symptomName eq 'Amenorrhoea'                   ||
                $symptomName eq 'Oligomenorrhoea'                 || $symptomName eq 'Oligomenorrhea'          || $symptomName eq 'Heavy menstrual bleeding'      ||
                $symptomName eq 'Menstrual disorder'              || $symptomName eq 'Haemorrhage'             || $symptomName eq 'Pelvic pain'                   ||
                $symptomName eq 'Ultrasound scan vagina abnormal' || $symptomName eq 'Dysmenorrhoea'           || $symptomName eq 'Polymenorrhoea'                ||
                $symptomName eq 'Breast swelling'                 || $symptomName eq 'Adnexa uteri pain'       || $symptomName eq 'Benign hydatidiform mole'      ||
                $symptomName eq 'Uterine haemorrhage'             || $symptomName eq 'Hysterectomy'            || $symptomName eq 'Fallopian tube operation'      ||
                $symptomName eq 'Breast cyst'                     || $symptomName eq 'Breast mass'             || $symptomName eq 'Polycystic ovaries'            ||
                $symptomName eq 'Infertility female'              || $symptomName eq 'Ovarian mass'            || $symptomName eq 'Ovarian granulosa cell tumour' ||
                $symptomName eq 'Amniorrhoea'                     || $symptomName eq 'Lactation disorder'      || $symptomName eq 'Ovulation disorder'
            ) {
                $symptoms .= '<li><span style="background:#f5d0f4;">' . $symptomName . '</span></li>';
            } else { # Symptoms are not of focus.
                $symptoms .= '<li><span>' . $symptomName . '</span></li>';
            }
        }
    }
    $symptoms .= '</ul></div>';

    $self->render(
        currentLanguage                 => $currentLanguage,
        operationsToPerform             => $operationsToPerform,
        seriousnessConfirmationRequired => $seriousnessConfirmationRequired,
        hospitalized                    => $hospitalized,
        permanentDisability             => $permanentDisability,
        lifeThreatning                  => $lifeThreatning,
        patientDied                     => $patientDied,
        childDied                       => $childDied,
        childSeriousAE                  => $childSeriousAE,
        reportId                        => $reportId,
        vaersId                         => $vaersId,
        symptoms                        => $symptoms,
        vaersVaccine                    => $vaersVaccine,
        vaersVaccineName                => $vaersVaccineName,
        vaersReceptionDate              => $vaersReceptionDate,
        vaccinationDate                 => $vaccinationDate,
        onsetDate                       => $onsetDate,
        vaersSex                        => $vaersSex,
        vaersSexName                    => $vaersSexName,
        aEDescription                   => $aEDescription,
        patientAge                      => $patientAge,
        creationDatetime                => $creationDatetime,
        seriousnessConfirmation         => $seriousnessConfirmation,
        seriousnessConfirmationRequired => $seriousnessConfirmationRequired,
        sqlValue                        => $sqlValue,
        languages                       => \%languages
    );
}

sub set_pregnancy_seriousness_attributes {
    my $self                     = shift;
    my $reportId                 = $self->param('reportId')            // die;
    my $patientDied              = $self->param('patientDied')         // die;
    my $lifeThreatning           = $self->param('lifeThreatning')      // die;
    my $permanentDisability      = $self->param('permanentDisability') // die;
    my $hospitalized             = $self->param('hospitalized')        // die;
    my $childDied                = $self->param('childDied')           // die;
    my $childSeriousAE           = $self->param('childSeriousAE')      // die;
    my $hoursBetweenVaccineAndAE = $self->param('hoursBetweenVaccineAndAE');
    my $vaccinationDate          = $self->param('vaccinationDate');
    my $onsetDate                = $self->param('onsetDate');
    my $vaccinationYear          = $self->param('vaccinationYear');
    my $vaccinationMonth         = $self->param('vaccinationMonth');
    my $vaccinationDay           = $self->param('vaccinationDay');
    my $onsetYear                = $self->param('onsetYear');
    my $onsetMonth               = $self->param('onsetMonth');
    my $onsetDay                 = $self->param('onsetDay');
    if (defined $hoursBetweenVaccineAndAE) {
        $hoursBetweenVaccineAndAE    = undef unless length $hoursBetweenVaccineAndAE >= 1;
    }
    my ($vaccinationDateFixed, $onsetDateFixed);
    if ($vaccinationYear && $vaccinationMonth && $vaccinationDay) {
        $vaccinationDateFixed = "$vaccinationYear-$vaccinationMonth-$vaccinationDay";
        $vaccinationDate      = "$vaccinationDateFixed";
    }
    if ($onsetYear && $onsetMonth && $onsetDay) {
        $onsetDateFixed       = "$onsetYear-$onsetMonth-$onsetDay";
        $onsetDate            = "$onsetDateFixed";
    }
    if ($onsetDate && $vaccinationDate && !defined $hoursBetweenVaccineAndAE) {
        $hoursBetweenVaccineAndAE = time::calculate_minutes_difference("$vaccinationDate 12:00:00", "$onsetDate 12:00:00");
        $hoursBetweenVaccineAndAE = nearest(0.01, ($hoursBetweenVaccineAndAE / 60));
    }
    say "reportId                 = $reportId";
    say "patientDied              = $patientDied";
    say "lifeThreatning           = $lifeThreatning";
    say "permanentDisability      = $permanentDisability";
    say "hospitalized             = $hospitalized";
    say "childDied                = $childDied";
    say "childSeriousAE           = $childSeriousAE";
    say "hoursBetweenVaccineAndAE = $hoursBetweenVaccineAndAE" if defined $hoursBetweenVaccineAndAE;
    $patientDied         = 1 if $patientDied eq 'true';
    $patientDied         = 0 if $patientDied eq 'false';
    $lifeThreatning      = 1 if $lifeThreatning eq 'true';
    $lifeThreatning      = 0 if $lifeThreatning eq 'false';
    $permanentDisability = 1 if $permanentDisability eq 'true';
    $permanentDisability = 0 if $permanentDisability eq 'false';
    $hospitalized        = 1 if $hospitalized eq 'true';
    $hospitalized        = 0 if $hospitalized eq 'false';
    $childDied           = 1 if $childDied eq 'true';
    $childDied           = 0 if $childDied eq 'false';
    $childSeriousAE      = 1 if $childSeriousAE eq 'true';
    $childSeriousAE      = 0 if $childSeriousAE eq 'false';

    my $sth      = $self->dbh->prepare("
        UPDATE vaers_fertility_report SET
            patientDiedFixed = $patientDied,
            lifeThreatningFixed = $lifeThreatning,
            permanentDisabilityFixed = $permanentDisability,
            hospitalizedFixed = $hospitalized,
            childDied = $childDied,
            childSeriousAE = $childSeriousAE,
            hoursBetweenVaccineAndAE = ?,
            vaccinationDateFixed = ?,
            onsetDateFixed = ?
        WHERE id = $reportId");
    $sth->execute($hoursBetweenVaccineAndAE, $vaccinationDateFixed, $onsetDateFixed) or die $sth->err();

    $self->render(text => 'ok');
}

sub vaers_fertility_symptoms {
    my $self = shift;
    my $currentLanguage  = $self->param('currentLanguage')  // die;
    my $vaersSymptomType = $self->param('vaersSymptomType') // die;

    say "vaersSymptomType : $vaersSymptomType";

    # Fetching vaers symptoms.
    my %symptoms = ();
    my $symptomsTitle;
    if ($vaersSymptomType eq 'excluded') {
        if ($currentLanguage eq 'en') {
            $symptomsTitle = 'Reports are excluded if they include at least one of the following symptoms :';
        } else {
            $symptomsTitle = "Les rapports sont exclus s'ils incluent au moins l'un des symptômes suivants :";
        }
        my $sTb = $self->dbh->selectall_hashref("SELECT id as symptomId, name as symptomName FROM vaers_fertility_symptom WHERE discarded = 1", 'symptomId');
        for my $symptomId (sort{$a <=> $b} keys %$sTb) {
            my $symptomName = %$sTb{$symptomId}->{'symptomName'} // die;
            $symptoms{$symptomName} = 1;
        }
    } elsif ($vaersSymptomType eq 'pregnancyRelated') {
        if ($currentLanguage eq 'en') {
            $symptomsTitle = 'Reports are considered as related to a pregnancy if they include at least one of the following symptoms :';
        } else {
            $symptomsTitle = "Les rapports sont considérés comme liés à une grossesse s'ils incluent au moins l'un des symptômes suivants :";
        }
        my $sTb = $self->dbh->selectall_hashref("SELECT id as symptomId, name as symptomName FROM vaers_fertility_symptom WHERE pregnancyRelated = 1", 'symptomId');
        for my $symptomId (sort{$a <=> $b} keys %$sTb) {
            my $symptomName = %$sTb{$symptomId}->{'symptomName'} // die;
            $symptoms{$symptomName} = 1;
        }
    } elsif ($vaersSymptomType eq 'severePregnancyRelated') {
        if ($currentLanguage eq 'en') {
            $symptomsTitle = 'Reports are considered as related to a pregnancy complication if they include at least one of the following symptoms :';
        } else {
            $symptomsTitle = "Les rapports sont considérés comme liés à une complication de grossesse s'ils incluent au moins l'un des symptômes suivants :";
        }
        my $sTb = $self->dbh->selectall_hashref("SELECT id as symptomId, name as symptomName FROM vaers_fertility_symptom WHERE severePregnancyRelated = 1", 'symptomId');
        for my $symptomId (sort{$a <=> $b} keys %$sTb) {
            my $symptomName = %$sTb{$symptomId}->{'symptomName'} // die;
            $symptoms{$symptomName} = 1;
        }
    } elsif ($vaersSymptomType eq 'foetalDeathRelated') {
        if ($currentLanguage eq 'en') {
            $symptomsTitle = 'Reports are considered as related to deadly outcome for the child or foetus if they include at least one of the following symptoms :';
        } else {
            $symptomsTitle = "Les rapports sont considérés comme liés à une issue fatale pour le foetus ou l'enfant s'ils incluent au moins l'un des symptômes suivants :";
        }
        my $sTb = $self->dbh->selectall_hashref("SELECT id as symptomId, name as symptomName FROM vaers_fertility_symptom WHERE foetalDeathRelated = 1", 'symptomId');
        for my $symptomId (sort{$a <=> $b} keys %$sTb) {
            my $symptomName = %$sTb{$symptomId}->{'symptomName'} // die;
            $symptoms{$symptomName} = 1;
        }
    } elsif ($vaersSymptomType eq 'severePregnancyNoDeathRelated') {
        if ($currentLanguage eq 'en') {
            $symptomsTitle = 'Reports are considered as related to a non-lethal pregnancy complication if they include at least one of the following symptoms :';
        } else {
            $symptomsTitle = "Les rapports sont considérés comme liés à une complication de grossesse non-fatale s'ils incluent au moins l'un des symptômes suivants :";
        }
        my $sTb = $self->dbh->selectall_hashref("SELECT id as symptomId, name as symptomName FROM vaers_fertility_symptom WHERE severePregnancyRelated = 1 AND foetalDeathRelated = 0", 'symptomId');
        for my $symptomId (sort{$a <=> $b} keys %$sTb) {
            my $symptomName = %$sTb{$symptomId}->{'symptomName'} // die;
            $symptoms{$symptomName} = 1;
        }
    } else {
        die "to code : [$vaersSymptomType]";
    }

    $self->render(
        currentLanguage  => $currentLanguage,
        vaersSymptomType => $vaersSymptomType,
        symptomsTitle    => $symptomsTitle,
        symptoms         => \%symptoms
    );
}

sub pregnancies_details {
    my $self = shift;

    # Loggin session if unknown.
    session::session_from_self($self);

    # Setting language & lang options.
    my $currentLanguage = $self->param('currentLanguage') // 'fr';
    my %languages       = ();
    $languages{'fr'}    = 'French';
    $languages{'en'}    = 'English';
    my %config          = %{$self->config()};
    my $environment     = $config{'environment'} // die;

    # Fetching total operations to perform.
    my $tb = $self->dbh->selectrow_hashref("SELECT count(id) as operationsToPerform FROM vaers_fertility_report WHERE pregnancyDetailsConfirmation IS NULL AND pregnancyDetailsConfirmationRequired = 1", undef);
    my $operationsToPerform = %$tb{'operationsToPerform'} // die;

    $self->render(
        currentLanguage     => $currentLanguage,
        operationsToPerform => $operationsToPerform,
        environment         => $environment,
        languages           => \%languages
    );
}

sub load_pregnancies_details {
    my $self = shift;

    # Loggin session if unknown.
    session::session_from_self($self);
    my %enums = %{$self->enums()};

    # Setting language & lang options.
    my $currentLanguage = $self->param('currentLanguage') // 'fr';
    my %languages       = ();
    $languages{'fr'}    = 'French';
    $languages{'en'}    = 'English';
    my %config          = %{$self->config()};
    my $environment     = $config{'environment'} // die;
    if ($environment ne "local") {
        $self->render(text => 'Disallowed');
    }

    # Fetching vaers symptoms.
    my %symptoms = ();
    my $sTb = $self->dbh->selectall_hashref("SELECT id as symptomId, name as symptomName, discarded FROM vaers_fertility_symptom", 'symptomId');
    for my $symptomId (sort{$a <=> $b} keys %$sTb) {
        my $symptomName = %$sTb{$symptomId}->{'symptomName'} // die;
        my $discarded   = %$sTb{$symptomId}->{'discarded'}   // die;
        $discarded      = unpack("N", pack("B32", substr("0" x 32 . $discarded, -32)));
        $symptoms{$symptomId}->{'symptomName'} = $symptomName;
        $symptoms{$symptomId}->{'discarded'}   = $discarded;
    }

    # Fetching confirmation target.
    my $operationsToPerform = $self->param('operationsToPerform') // die;
    my $sqlParam            = 'pregnancyDetailsConfirmationRequired';
    my $sqlValue            = 'pregnancyDetailsConfirmation';
    my $rTb                 = $self->dbh->selectrow_hashref("
        SELECT
            id as reportId,
            vaersId,
            vaersVaccine,
            vaersSex,
            patientAge,
            creationTimestamp,
            aEDescription,
            vaersReceptionDate,
            onsetDate,
            lmpDate,
            vaccinationDateFixed,
            onsetDateFixed,
            vaccinationDate,
            pregnancyDetailsConfirmation,
            pregnancyDetailsConfirmationRequired,
            hoursBetweenVaccineAndAE,
            childDied,
            childSeriousAE,
            motherAgeFixed,
            miscarriageOnWeek,
            childAgeWeekFixed,
            hospitalized,
            permanentDisability,
            lifeThreatning,
            patientDied,
            symptomsListed
        FROM vaers_fertility_report
        WHERE
            $sqlValue IS NULL AND
            $sqlParam = 1
        LIMIT 1", undef); # ORDER BY RAND()
    my $reportId                             = %$rTb{'reportId'}                        // die;
    my $vaersId                              = %$rTb{'vaersId'}                         // die;
    my $vaersVaccine                         = %$rTb{'vaersVaccine'}                    // die;
    my $vaersVaccineName                     = $enums{'vaersVaccine'}->{$vaersVaccine}  // die;
    my $vaersSex                             = %$rTb{'vaersSex'}                        // die;
    my $vaersSexName                         = $enums{'vaersSex'}->{$vaersSex}          // die;
    my $patientAge                           = %$rTb{'patientAge'};
    my $childAgeWeekFixed                    = %$rTb{'childAgeWeekFixed'};
    my $hoursBetweenVaccineAndAE             = %$rTb{'hoursBetweenVaccineAndAE'};
    my $motherAgeFixed                       = %$rTb{'motherAgeFixed'};
    my $miscarriageOnWeek                    = %$rTb{'miscarriageOnWeek'};
    my $creationTimestamp                    = %$rTb{'creationTimestamp'}               // die;
    my $creationDatetime                     = time::timestamp_to_datetime($creationTimestamp);
    my $aEDescription                        = %$rTb{'aEDescription'}                   // die;
    my $vaersReceptionDate                   = %$rTb{'vaersReceptionDate'}              // die;
    my $pregnancyDetailsConfirmationRequired = %$rTb{'pregnancyDetailsConfirmationRequired'} // die;
    $pregnancyDetailsConfirmationRequired    = unpack("N", pack("B32", substr("0" x 32 . $pregnancyDetailsConfirmationRequired, -32)));
    my $hospitalized                         = %$rTb{'hospitalized'}        // die;
    $hospitalized                            = unpack("N", pack("B32", substr("0" x 32 . $hospitalized, -32)));
    my $permanentDisability                  = %$rTb{'permanentDisability'} // die;
    $permanentDisability                     = unpack("N", pack("B32", substr("0" x 32 . $permanentDisability, -32)));
    my $lifeThreatning                       = %$rTb{'lifeThreatning'}      // die;
    $lifeThreatning                          = unpack("N", pack("B32", substr("0" x 32 . $lifeThreatning, -32)));
    my $patientDied                          = %$rTb{'patientDied'}         // die;
    $patientDied                             = unpack("N", pack("B32", substr("0" x 32 . $patientDied, -32)));
    my $childDied                            = %$rTb{'childDied'}           // die;
    $childDied                               = unpack("N", pack("B32", substr("0" x 32 . $childDied, -32)));
    my $childSeriousAE                       = %$rTb{'childSeriousAE'}      // die;
    $childSeriousAE                          = unpack("N", pack("B32", substr("0" x 32 . $childSeriousAE, -32)));
    my $vaccinationDate                      = %$rTb{'vaccinationDate'};
    my $onsetDate                            = %$rTb{'onsetDate'};
    my $vaccinationDateFixed                 = %$rTb{'vaccinationDateFixed'};
    my $onsetDateFixed                       = %$rTb{'onsetDateFixed'};
    my $pregnancyDetailsConfirmation         = %$rTb{'pregnancyDetailsConfirmation'};
    my $lmpDate                              = %$rTb{'lmpDate'};
    my ($lmpYear, $lmpMonth, $lmpDay);
    if ($lmpDate) {
        ($lmpYear, $lmpMonth, $lmpDay) = split '-', $lmpDate;
    }

    $aEDescription =~ s/age/\<span style=\"background:yellow;\"\>age\<\/span\>/g;
    $aEDescription =~ s/Age/\<span style=\"background:yellow;\"\>Age\<\/span\>/g;
    $aEDescription =~ s/AGE/\<span style=\"background:yellow;\"\>AGE\<\/span\>/g;
    $aEDescription =~ s/year/\<span style=\"background:yellow;\"\>year\<\/span\>/g;
    $aEDescription =~ s/Year/\<span style=\"background:yellow;\"\>Year\<\/span\>/g;
    $aEDescription =~ s/YEAR/\<span style=\"background:yellow;\"\>YEAR\<\/span\>/g;
    $aEDescription =~ s/lmp/\<span style=\"background:yellow;\"\>lmp\<\/span\>/g;
    $aEDescription =~ s/Lmp/\<span style=\"background:yellow;\"\>Lmp\<\/span\>/g;
    $aEDescription =~ s/LMP/\<span style=\"background:yellow;\"\>LMP\<\/span\>/g;
    $aEDescription =~ s/last menstrual period/\<span style=\"background:yellow;\"\>last menstrual period\<\/span\>/g;
    $aEDescription =~ s/Last Menstrual Period/\<span style=\"background:yellow;\"\>Last Menstrual Period\<\/span\>/g;
    $aEDescription =~ s/LAST MENSTRUAL PERIOD/\<span style=\"background:yellow;\"\>LAST MENSTRUAL PERIOD\<\/span\>/g;
    $aEDescription =~ s/yo/\<span style=\"background:yellow;\"\>yo\<\/span\>/g;
    $aEDescription =~ s/Yo/\<span style=\"background:yellow;\"\>Yo\<\/span\>/g;
    $aEDescription =~ s/YO/\<span style=\"background:yellow;\"\>YO\<\/span\>/g;
    $aEDescription =~ s/week/\<span style=\"background:yellow;\"\>week\<\/span\>/g;
    $aEDescription =~ s/Week/\<span style=\"background:yellow;\"\>Week\<\/span\>/g;
    $aEDescription =~ s/WEEK/\<span style=\"background:yellow;\"\>WEEK\<\/span\>/g;
    $aEDescription =~ s/day/\<span style=\"background:yellow;\"\>day\<\/span\>/g;
    $aEDescription =~ s/Day/\<span style=\"background:yellow;\"\>Day\<\/span\>/g;
    $aEDescription =~ s/DAY/\<span style=\"background:yellow;\"\>DAY\<\/span\>/g;
    $aEDescription =~ s/old/\<span style=\"background:yellow;\"\>old\<\/span\>/g;
    $aEDescription =~ s/Old/\<span style=\"background:yellow;\"\>Old\<\/span\>/g;
    $aEDescription =~ s/OLD/\<span style=\"background:yellow;\"\>OLD\<\/span\>/g;
    $aEDescription =~ s/trimester/\<span style=\"background:yellow;\"\>trimester\<\/span\>/g;
    $aEDescription =~ s/Trimester/\<span style=\"background:yellow;\"\>Trimester\<\/span\>/g;
    $aEDescription =~ s/TRIMESTER/\<span style=\"background:yellow;\"\>TRIMESTER\<\/span\>/g;
    my $symptomsListed                = %$rTb{'symptomsListed'}  // die;
    $symptomsListed                   = decode_json($symptomsListed);
    my $symptoms = '<div style="width:300px;margin:auto;"><ul>';
    for my $symptomId (@$symptomsListed) {
        my $symptomName = $symptoms{$symptomId}->{'symptomName'} // die;
        my $discarded   = $symptoms{$symptomId}->{'discarded'}   // die;
        $symptoms .= '<li><span>' . $symptomName . '</span></li>';
    }
    $symptoms .= '</ul></div>';
    my ($vaccinationYear, $vaccinationMonth, $vaccinationDay)  = split '-', $vaccinationDate;
    if ($vaccinationDateFixed) {
        ($vaccinationYear, $vaccinationMonth, $vaccinationDay) = split '-', $vaccinationDateFixed;
    }
    my ($onsetYear, $onsetMonth, $onsetDay)  = split '-', $onsetDate;
    if ($onsetDateFixed) {
        ($onsetYear, $onsetMonth, $onsetDay) = split '-', $onsetDateFixed;
    }

    $self->render(
        currentLanguage                      => $currentLanguage,
        operationsToPerform                  => $operationsToPerform,
        hospitalized                         => $hospitalized,
        permanentDisability                  => $permanentDisability,
        lifeThreatning                       => $lifeThreatning,
        patientDied                          => $patientDied,
        childDied                            => $childDied,
        childSeriousAE                       => $childSeriousAE,
        reportId                             => $reportId,
        vaersId                              => $vaersId,
        symptoms                             => $symptoms,
        vaersVaccine                         => $vaersVaccine,
        vaersVaccineName                     => $vaersVaccineName,
        vaersReceptionDate                   => $vaersReceptionDate,
        vaccinationDate                      => $vaccinationDate,
        vaccinationDateFixed                 => $vaccinationDateFixed,
        vaccinationYear                      => $vaccinationYear,
        vaccinationMonth                     => $vaccinationMonth,
        vaccinationDay                       => $vaccinationDay,
        onsetDate                            => $onsetDate,
        onsetDateFixed                       => $onsetDateFixed,
        onsetYear                            => $onsetYear,
        onsetMonth                           => $onsetMonth,
        onsetDay                             => $onsetDay,
        lmpYear                              => $lmpYear,
        lmpMonth                             => $lmpMonth,
        lmpDay                               => $lmpDay,
        lmpDate                              => $lmpDate,
        vaersSex                             => $vaersSex,
        vaersSexName                         => $vaersSexName,
        aEDescription                        => $aEDescription,
        patientAge                           => $patientAge,
        motherAgeFixed                       => $motherAgeFixed,
        childAgeWeekFixed                    => $childAgeWeekFixed,
        miscarriageOnWeek                    => $miscarriageOnWeek,
        creationDatetime                     => $creationDatetime,
        hoursBetweenVaccineAndAE             => $hoursBetweenVaccineAndAE,
        pregnancyDetailsConfirmation         => $pregnancyDetailsConfirmation,
        pregnancyDetailsConfirmationRequired => $pregnancyDetailsConfirmationRequired,
        sqlValue                             => $sqlValue,
        languages                            => \%languages
    );
}

sub set_pregnancy_details_attributes {
    my $self              = shift;
    my $reportId          = $self->param('reportId')            // die;
    my $motherAgeFixed    = $self->param('motherAgeFixed');
    my $childAgeWeekFixed = $self->param('childAgeWeekFixed');
    my $miscarriageOnWeek = $self->param('miscarriageOnWeek');
    $motherAgeFixed       = undef unless length $motherAgeFixed    >= 1;
    $childAgeWeekFixed    = undef unless length $childAgeWeekFixed >= 1;
    $miscarriageOnWeek    = undef unless length $miscarriageOnWeek >= 1;
    my $lmpYear           = $self->param('lmpYear');
    my $lmpMonth          = $self->param('lmpMonth');
    my $lmpDay            = $self->param('lmpDay');
    my $lmpDate;
    if ($lmpYear && $lmpMonth && $lmpDay) {
        $lmpDate          = "$lmpYear-$lmpMonth-$lmpDay";
    }
    my $hoursBetweenVaccineAndAE = $self->param('hoursBetweenVaccineAndAE');
    my $vaccinationDate          = $self->param('vaccinationDate');
    my $onsetDate                = $self->param('onsetDate');
    my $vaccinationYear          = $self->param('vaccinationYear');
    my $vaccinationMonth         = $self->param('vaccinationMonth');
    my $vaccinationDay           = $self->param('vaccinationDay');
    my $onsetYear                = $self->param('onsetYear');
    my $onsetMonth               = $self->param('onsetMonth');
    my $onsetDay                 = $self->param('onsetDay');
    if (defined $hoursBetweenVaccineAndAE) {
        $hoursBetweenVaccineAndAE = undef unless length $hoursBetweenVaccineAndAE >= 1;
    }
    my ($vaccinationDateFixed, $onsetDateFixed);
    if ($vaccinationYear && $vaccinationMonth && $vaccinationDay) {
        $vaccinationDateFixed = "$vaccinationYear-$vaccinationMonth-$vaccinationDay";
        $vaccinationDate      = "$vaccinationDateFixed";
    }
    if ($onsetYear && $onsetMonth && $onsetDay) {
        $onsetDateFixed       = "$onsetYear-$onsetMonth-$onsetDay";
        $onsetDate            = "$onsetDateFixed";
    }
    if ($onsetDate && $vaccinationDate && !defined $hoursBetweenVaccineAndAE) {
        $hoursBetweenVaccineAndAE = time::calculate_minutes_difference("$vaccinationDate 12:00:00", "$onsetDate 12:00:00");
        $hoursBetweenVaccineAndAE = nearest(0.01, ($hoursBetweenVaccineAndAE / 60));
    }
    my $sth               = $self->dbh->prepare("
        UPDATE vaers_fertility_report SET
            motherAgeFixed = ?,
            childAgeWeekFixed = ?,
            miscarriageOnWeek = ?,
            lmpDate = ?,
            hoursBetweenVaccineAndAE = ?,
            vaccinationDateFixed = ?,
            onsetDateFixed = ?
        WHERE id = $reportId");
    $sth->execute($motherAgeFixed, $childAgeWeekFixed, $miscarriageOnWeek, $lmpDate, $hoursBetweenVaccineAndAE, $vaccinationDateFixed, $onsetDateFixed) or die $sth->err();

    $self->render(text => 'ok');
}

sub display_reports {
    my $self            = shift;
    my $currentLanguage = $self->param('currentLanguage') // die;
    my $reportType      = $self->param('reportType')      // die;
    my $reportNum       = $self->param('reportNum')       // die;
    my %enums           = %{$self->enums()};
    say "reportType : $reportType";

    # Fetching reports according to the report type.
    my $totalReports   = 0;
    my %report = ();
    for my $reportFile (glob "stats/$reportType/*.json") {
        $totalReports++;
        if ($totalReports == $reportNum) {
            open my $in, '<:utf8', $reportFile;
            my $json;
            while (<$in>) {
                $json = $_;
            }
            close $in;
            $json = decode_json($json);
            %report = %$json;
        }
    }

    $self->render(
        reportType   => $reportType,
        reportNum    => $reportNum,
        totalReports => $totalReports,
        report       => \%report
    );
}

1;