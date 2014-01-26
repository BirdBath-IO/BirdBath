package BirdBath::Controller::Manage;

use Mojo::Base 'Mojolicious::Controller';

use Mango::BSON qw/ bson_oid bson_time/;
use Net::Twitter;

sub welcome {
  my $self = shift;

  $self->render();
}

1;
