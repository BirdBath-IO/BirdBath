package BirdBath::Github;

use Mojo::Base 'Mojolicious::Controller';

sub github {
  my $self = shift;

  my $client_id = $self->config->{github}->{client_id};
  my $client_secret = $self->config->{github}->{client_secret};
  my $redirect_uri = $self->config->{github}->{redirect_uri};

  my $code = $self->req->url->query->param('code');
  if(!$code) {
    my $state = "something";
    $self->session('state' => $state);

    my $url = "https://github.com/login/oauth/authorize?client_id=$client_id&redirect_uri=$redirect_uri&scope=&state=$state";
    return $self->redirect_to($url);
  }

  my $rstate = $self->req->url->query->param('state');
  my $state = $self->session('state');

  if($rstate ne $state) {
    return $self->render_exception("Invalid state");
  }

  my $url = "https://github.com/login/oauth/access_token?client_id=$client_id&client_secret=$client_secret&code=$code&redirect_uri=$redirect_uri";
  $self->ua->post($url => { Accept => 'application/json' } => sub {
    my ($ua, $tx) = @_;

    if($tx->success) {

      $url = "https://api.github.com/user?access_token=" . $tx->res->json->{access_token};
      $self->ua->get($url => sub {
        my ($ua, $tx) = @_;

        if($tx->success) {
          my $user = $tx->res->json;
          $self->users->find_one({"id" => $user->{id}} => sub {
            my ($mango, $error, $doc) = @_;

            return $self->render_exception("DB error") if $error;

            if($doc) {
              $self->session(user => $doc);
              $self->redirect_to('/');
            } else {
              $self->users->find({})->count(sub {
                my ($mango, $error, $count) = @_;
                return $self->render_exception("DB error") if $error;

                if($count == 0) {
                  $user->{_birdbath}->{role} = "Admin";
                } else {
                  $user->{_birdbath}->{role} = "Contributor";
                }
                $self->users->insert($user => sub {
                  my ($mango, $error, $doc) = @_;
                  return $self->render_exception("DB error") if $error;

                  $self->session(user => $user);
                  $self->redirect_to('/');
                });
              });
            }
          });
        } else {
          $self->render_exception("Error getting user profile");
        }
      });
    } else {
      use Data::Dumper; print Dumper $tx;
      $self->render_exception("Error getting access token");
    }
  });

  $self->render_later;
}

1;