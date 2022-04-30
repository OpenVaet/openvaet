package OpenVaet::Controller::DataGouvFr;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Data::Printer;
use FindBin;
use lib "$FindBin::Bin/../lib";

sub data_gouv_fr {
    my $self = shift;


    $self->render(
    );
}

1;