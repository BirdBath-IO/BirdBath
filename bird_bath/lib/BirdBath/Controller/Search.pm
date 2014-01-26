package BirdBath::Controller::Search;

use Mojo::Base 'Mojolicious::Controller';

use Net::Twitter;

sub timeline {
	my $self = shift;

	my $username = $self->req->json->{username};

	my $nt = Net::Twitter->new(
	    traits   => [qw/API::RESTv1_1/],
	    ssl => 1,
	    consumer_key        => $self->config->{twitter}->{consumer_key},
	    consumer_secret     => $self->config->{twitter}->{consumer_secret},
	    access_token        => $self->config->{twitter}->{access_token},
		access_token_secret => $self->config->{twitter}->{access_token_secret},
	);

	my $tweets = $nt->user_timeline({screen_name => $username});

	$self->render(json => $tweets);
}

sub search {
	my $self = shift;

	my $search = $self->req->json->{search};

	my $nt = Net::Twitter->new(
	    traits   => [qw/API::RESTv1_1/],
	    ssl => 1,
	    consumer_key        => $self->config->{twitter}->{consumer_key},
	    consumer_secret     => $self->config->{twitter}->{consumer_secret},
	    access_token        => $self->config->{twitter}->{access_token},
		access_token_secret => $self->config->{twitter}->{access_token_secret},
	);

	my $tweets = $nt->search($search);

	$self->render(json => $tweets->{statuses});
}

1;
