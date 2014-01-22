package BirdBath::Twitter;

use Mojo::Base 'Mojolicious::Controller';
use Net::Twitter;

sub twitter {
  my $self = shift;

  my $callback = $self->config->{twitter}->{callback};

  my $nt = Net::Twitter->new(
      traits   => [qw/API::RESTv1_1 OAuth/],
      ssl => 1,
      consumer_key        => $self->config->{twitter}->{consumer_key},
      consumer_secret     => $self->config->{twitter}->{consumer_secret},
      #access_token        => $token,
      #access_token_secret => $token_secret,
  );
  my $url = $nt->get_authorization_url(callback => $callback);

  $self->session(twitter_oauth => {
    token => $nt->request_token,
    token_secret => $nt->request_token_secret,
  });

  $self->redirect_to($url);
}

sub callback {
  my $self = shift;

  my $token = $self->session->{twitter_oauth}->{token};
  my $secret = $self->session->{twitter_oauth}->{token_secret};

  my $nt = Net::Twitter->new(
      traits   => [qw/API::RESTv1_1 OAuth/],
      ssl => 1,
      consumer_key        => $self->config->{twitter}->{consumer_key},
      consumer_secret     => $self->config->{twitter}->{consumer_secret},
  );

  my $verify = $self->param('oauth_verifier');

  $nt->request_token($token);
  $nt->request_token_secret($secret);

  my($access_token, $access_token_secret, $user_id, $screen_name)
        = $nt->request_access_token(verifier => $verify);

  $self->accounts->update({user_id => $user_id},{
    user_id => $user_id,
    screen_name => $screen_name,
    access_token => $access_token,
    access_token_secret => $access_token_secret,
  },{upsert => 1} => sub {
    my ($mango, $error, $doc) = @_;

    die("DB error") if $error;

    $self->redirect_to('/');
  });
}

1;