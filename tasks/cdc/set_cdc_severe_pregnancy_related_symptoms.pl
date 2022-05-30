#!/usr/bin/perl
use strict;
use warnings;
use 5.30.0;
no autovivification;
binmode STDOUT, ":utf8";
use utf8;
use open ':std', ':encoding(UTF-8)';
use Data::Printer;
use JSON;
use Text::CSV qw( csv );
use Encode;
use Encode::Unicode;
use Scalar::Util qw(looks_like_number);
use FindBin;
use lib "$FindBin::Bin/../../lib";
use global;

my @symptoms = ( 'Foetal heart rate abnormal' , 'Premature labour' , 'Cleft lip' , 'Maternal exposure timing unspecified' ,
                    'Premature baby' , 'Foetal disorder' ,
                    'Uterine dilation and curettage' , 'Cleft lip and palate' ,
                    'Foetal cardiac arrest' , 'Stillbirth' ,
                    'Foetal hypokinesia' , 'Abortion missed' ,
                    'Labour induction' , 'Premature separation of placenta' ,
                    'Hydrops foetalis' , 'Premature delivery' , 'Ultrasound foetal abnormal' ,
                    'Failed induction of labour' , 'Gestational hypertension' ,
                    'Placental disorder' , 'Ectopic pregnancy' ,
                    'Foetal growth restriction' , 'Placental insufficiency' ,
                    'Umbilical cord abnormality' , 'Ultrasound antenatal screen abnormal' ,
                    'Umbilical cord around neck' , 'Complication of pregnancy' ,
                    'Foetal chromosome abnormality' , 'Foetal cystic hygroma' , 'Abortion' ,
                    'Bradycardia foetal' , 'Haemorrhage in pregnancy' ,
                    'Low birth weight baby' , 'Induced labour' , 'Tachycardia foetal' ,
                    'Amniotic cavity infection' , 'Premature rupture of membranes' , 'Abortion spontaneous complete' ,
                    'Abortion threatened' , 'Uterine dilation and evacuation' , 'Foetal growth abnormality' ,
                    'Foetal renal impairment' , 'Cerebral haemorrhage foetal' , 'Foetal placental thrombosis' ,
                    'Human chorionic gonadotropin increased' , 'Foetal cardiac disorder');





for my $symptomName (@symptoms) {
    say "symptomName : $symptomName";
    my $sTb = $dbh->selectrow_hashref("SELECT id as symptomId FROM vaers_fertility_symptom WHERE name = ?", undef, $symptomName);
    die unless $sTb && %$sTb{'symptomId'};
    my $symptomId = %$sTb{'symptomId'} // die;

    say "symptomId : $symptomId";
    my $sth = $dbh->prepare("UPDATE vaers_fertility_symptom SET severePregnancyRelated = 1, severePregnancyRelatedTimestamp = UNIX_TIMESTAMP() WHERE id = $symptomId");
    $sth->execute() or die $sth->err();
}