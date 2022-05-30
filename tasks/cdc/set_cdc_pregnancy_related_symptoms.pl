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

my @symptoms = ('Exposure during pregnancy', 'Maternal exposure during pregnancy', 'Pregnancy',
                'Maternal exposure before pregnancy', 'Maternal exposure during breast feeding', 'Foetal heart rate abnormal',
                'Premature labour', 'Cleft lip', 'Maternal exposure timing unspecified',
                'Premature baby', 'Pregnancy test positive', 'Foetal disorder',
                'Foetal exposure during pregnancy', 'Uterine dilation and curettage', 'Cleft lip and palate',
                'Foetal cardiac arrest', 'Pregnancy test positive', 'Stillbirth',
                'Foetal hypokinesia', 'Foetal non-stress test normal', 'Abortion missed',
                'Labour induction', 'Amniotic fluid index decreased', 'Ultrasound antenatal screen normal',
                'Hydrops foetalis', 'Premature delivery', 'Ultrasound foetal abnormal',
                'Caesarean section', 'Failed induction of labour', 'Gestational hypertension',
                'Ultrasound foetal', 'Placental disorder', 'Ectopic pregnancy',
                'Foetal growth restriction', 'Placental insufficiency', 'Foetal death',
                'Umbilical cord abnormality', 'Amniocentesis', 'Ultrasound antenatal screen abnormal',
                'Umbilical cord around neck', 'Ultrasound antenatal screen abnormal', 'Complication of pregnancy',
                'Foetal chromosome abnormality', 'Foetal cystic hygroma', 'Abortion',
                'Bradycardia foetal', 'Foetal monitoring', 'Foetal non-stress test',
                'Low birth weight baby', 'Induced labour', 'Tachycardia foetal',
                'Amniotic cavity infection', 'Premature rupture of membranes', 'Abortion spontaneous',
                'Anembryonic gestation', 'Abortion spontaneous complete', 'First trimester pregnancy',
                'Abortion threatened', 'Haemorrhage in pregnancy', 'Uterine dilation and evacuation',
                'Premature separation of placenta', 'Prenatal screening test', 'Foetal growth abnormality',
                'Foetal renal impairment', 'Exposure during pregnancy', 'Maternal exposure during pregnancy', 'Pregnancy',
                'Maternal exposure before pregnancy', 'Maternal exposure during breast feeding', 'Foetal heart rate abnormal',
                'Premature labour', 'Cleft lip', 'Maternal exposure timing unspecified',
                'Premature baby', 'Pregnancy test positive', 'Foetal disorder',
                'Foetal exposure during pregnancy', 'Uterine dilation and curettage', 'Cleft lip and palate',
                'Foetal cardiac arrest', 'Pregnancy test positive', 'Stillbirth',
                'Foetal hypokinesia', 'Foetal non-stress test normal', 'Abortion missed',
                'Labour induction', 'Amniotic fluid index decreased', 'Ultrasound antenatal screen normal',
                'Hydrops foetalis', 'Premature delivery', 'Ultrasound foetal abnormal',
                'Caesarean section', 'Failed induction of labour', 'Gestational hypertension',
                'Ultrasound foetal', 'Placental disorder', 'Ectopic pregnancy',
                'Foetal growth restriction', 'Placental insufficiency', 'Foetal death',
                'Umbilical cord abnormality', 'Amniocentesis', 'Ultrasound antenatal screen abnormal',
                'Umbilical cord around neck', 'Ultrasound antenatal screen abnormal', 'Complication of pregnancy',
                'Foetal chromosome abnormality', 'Foetal cystic hygroma', 'Abortion',
                'Bradycardia foetal', 'Foetal monitoring', 'Foetal non-stress test',
                'Low birth weight baby', 'Induced labour', 'Tachycardia foetal',
                'Amniotic cavity infection', 'Premature rupture of membranes', 'Abortion spontaneous',
                'Anembryonic gestation', 'Abortion spontaneous complete', 'First trimester pregnancy',
                'Abortion threatened', 'Haemorrhage in pregnancy', 'Uterine dilation and evacuation',
                'Premature separation of placenta', 'Prenatal screening test', 'Foetal growth abnormality',
                'Foetal renal impairment', 'Cerebral haemorrhage foetal', 'Foetal placental thrombosis',
                'Human chorionic gonadotropin increased', 'Foetal cardiac disorder');


for my $symptomName (@symptoms) {
    say "symptomName : $symptomName";
    my $sTb = $dbh->selectrow_hashref("SELECT id as symptomId FROM vaers_fertility_symptom WHERE name = ?", undef, $symptomName);
    die unless $sTb && %$sTb{'symptomId'};
    my $symptomId = %$sTb{'symptomId'} // die;

    say "symptomId : $symptomId";
    my $sth = $dbh->prepare("UPDATE vaers_fertility_symptom SET pregnancyRelated = 1, pregnancyRelatedTimestamp = UNIX_TIMESTAMP() WHERE id = $symptomId");
    $sth->execute() or die $sth->err();
}