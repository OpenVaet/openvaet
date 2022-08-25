package OpenVaet::Controller::AustralianData;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Data::Printer;
use FindBin;
use lib "$FindBin::Bin/../lib";
use session;
use data_formatting;

sub australian_data {

    my $self = shift;
    my $currentLanguage = $self->param('currentLanguage') // 'en';

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    my $australianData;
    open my $in, '<:utf8', 'usa_and_foreign_death_reports.json';
    while (<$in>) {
        $australianData .= $_;
    }
    close $in;
    $australianData = decode_json($australianData);
    my %australianData = %$australianData;


    $self->render(
        currentLanguage => $currentLanguage,
        languages       => \%languages,
        australianData  => \%australianData
    );
}

sub australian_symptoms {

    my $self = shift;
    my $currentLanguage = $self->param('currentLanguage') // 'en';

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    my %ausSymptoms = ();
	my $tb = $self->dbh->selectall_hashref("SELECT id as ausSymptomId, name as ausSymptomName, timeSeen, active FROM aus_symptom", 'ausSymptomId');
	for my $ausSymptomId (sort{$a <=> $b} keys %$tb) {
		my $ausSymptomName = %$tb{$ausSymptomId}->{'ausSymptomName'} // die;
		my $timeSeen       = %$tb{$ausSymptomId}->{'timeSeen'}       // die;
		my $active         = %$tb{$ausSymptomId}->{'active'}         // die;
		$active            = unpack("N", pack("B32", substr("0" x 32 . $active, -32)));
		$ausSymptoms{$ausSymptomName}->{'ausSymptomId'} = $ausSymptomId;
		$ausSymptoms{$ausSymptomName}->{'timeSeen'} = $timeSeen;
		$ausSymptoms{$ausSymptomName}->{'active'} = $active;
	}

    $self->render(
        currentLanguage => $currentLanguage,
        languages       => \%languages,
        ausSymptoms     => \%ausSymptoms
    );
}

sub set_symptom_activity {
	my $self = shift;

	my $ausSymptomId = $self->param('ausSymptomId') // die;
	my $activity = $self->param('activity') // die;

	my $sth = $self->dbh->prepare("UPDATE aus_symptom SET active = $activity, activeTimestamp = UNIX_TIMESTAMP() WHERE id = $ausSymptomId");
	$sth->execute() or die $sth->err();

	say "setting [$ausSymptomId] on [$activity]";

	$self->render(text => 'ok');
}

1;