# max demmelbauer
# 28-10-06
#
# implements an comet server
#
# the client connection type is specified by the get request:
#   /event1/event2?key1=value2&key2=value2
#          |                    |
#      events listen for    parameters

package WebTek::Script;

sub comet :Info(comet starts a comet server) {
   my $config = config('comet');
   print "start WebTek Coment Server...\n";
   print "  Emitter: $config->{'emitter'}->{'port'}\n";
   print "  Collector: $config->{'collector'}->{'port'}\n";
   app::Model::Cometd->start(
      CollectorHost => $config->{'collector'}->{'host'},
      CollectorPort => $config->{'collector'}->{'port'},
      EmitterHost => $config->{'emitter'}->{'host'},
      EmitterPort => $config->{'emitter'}->{'port'},
      Debug => app->log_level eq WebTek::Logger::LOG_LEVEL_DEBUG(),
   );
}

package app::Model::Cometd;

use bytes;
use WebTek::Export qw( comet_event );
use POE qw(Component::Server::TCP Filter::Stream);

# ---------------------------------------------------------------------------
# utils
# ---------------------------------------------------------------------------

sub comet_event {
   my $event = shift;   # string with eventname (Appname.event or event)
   my $data = shift;    # string or obj (will converted to json)

   #... create event name with format Appname.eventname
   $event = app->name . ".$event" unless $event =~ /\./;
   #... connect to collector
   my $put = IO::Socket::INET->new(
      Proto => 'tcp',
      PeerAddr => config('comet')->{'collector'}->{'host'},
      PeerPort => config('comet')->{'collector'}->{'port'},
   ) or throw "cannot connect to comet-server";
   print $put "$event\n" . struct($data) . "\n";
   close $put;
}

# ---------------------------------------------------------------------------
# server
# ---------------------------------------------------------------------------

our $Events = {};

sub start {
   my $class = shift;
   my %args = @_;
   
   assert($args{'CollectorHost'}, 'CollectorHost not defined');
   assert($args{'CollectorPort'}, 'CollectorPort not defined');
   assert($args{'EmitterHost'}, 'EmitterHost not defined');
   assert($args{'EmitterPort'}, 'EmitterPort not defined');
   my $debug = $args{'Debug'};
   
   #... init the event-put server
   POE::Component::Server::TCP->new(
      Alias => "collector",
      Hostname => $args{'CollectorHost'},
      Port => $args{'CollectorPort'},
      ClientInput => sub {
         my ($heap, $input) = @_[HEAP, ARG0];
         unless ($heap->{'event'}) { $heap->{'event'} = $input }
         else { $heap->{'msg'} .= $input }
      },
      ClientDisconnected => sub {
         my ($kernel, $heap) = @_[KERNEL, HEAP];
         $debug and print "broadcast event '$heap->{'event'}'\n";
         return unless $Events->{$heap->{'event'}};
         foreach my $session (@{$Events->{$heap->{'event'}}}) {
            $kernel->post($session, "notify", $heap->{'event'}, $heap->{'msg'});
         }
      },
   );
   #... init the event listen server
   POE::Component::Server::TCP->new(
      Alias => "emitter",
      Hostname => $args{'EmitterHost'},
      Port => $args{'EmitterPort'},
      ClientFilter => 'POE::Filter::Stream',
      ClientInput => sub {
         my ($kernel, $session, $heap, $input) =
            @_[KERNEL, SESSION, HEAP, ARG0];
         #... check for an valid request
         unless ($input =~ /^GET \/([\w\.\/]+)\??(\S*)/) {
            $debug and print "bad request: '$input'\n";
            $heap->{'client'}->put(
               "HTTP/1.0 200 OK\r\n" .
               "Server: WebTek Comet\r\n" .
               "Content-Type: text/html; charset=UTF-8\r\n\r\n" .
               "only GET requests are supported\r\n\r\n"
            );
            $kernel->yield("shutdown");
            return;            
         }
         #... cancel connection shutdown
         $heap->{'do_shutdown'} = 0;
         #... remember events for this session
         my @events = split "/", $1;
         $heap->{'events'} = \@events;
         $heap->{'params'} = {};
         foreach my $param (split "&", decode_url($2)) {
            if ($param =~ /(\w+)=(.*)/) { $heap->{'params'}->{$1} = $2 }
         }
         foreach my $event (@events) {
            next if grep { $session == $_ } @{$Events->{$event}};
            $debug and print
               "register event '$event' for session " . $session->ID . "\n";
            unless ($Events->{$event}) { $Events->{$event} = [] }
            push @{$Events->{$event}}, $session;
         }
         $heap->{'client'}->put(
            "HTTP/1.1 200 OK\r\n" .
            "Server: WebTek Comet\r\n" .
            "Keep-Alive: timeout=2, max=100\r\n" .
            "Connection: Keep-Alive\r\n" .
            "Transfer-Encoding: chunked\r\n" .
            "Content-Type: text/javascript; charset=UTF-8\r\n\r\n"
         );
         $heap->{'waiting'} = 1;
         if ($heap->{'queue'} and @{$heap->{'queue'}}) {
            my $event = shift @{$heap->{'queue'}};
            $kernel->post($session, "notify", $event->[0], $event->[1]);
         }
      },
      ClientDisconnected => sub {
         my ($session, $heap) = @_[SESSION, HEAP];
         foreach my $event (@{$heap->{'events'}}) {
            $debug and print
               "deregister event '$event' for session " . $session->ID . "\n";
            my @active = grep { $_->ID != $session->ID } @{$Events->{$event}};
            $Events->{$event} = \@active;
         }
      },
      InlineStates => {
         "notify" => sub {
            my ($kernel, $session, $heap, $event, $msg) =
               @_[KERNEL, SESSION, HEAP, ARG0, ARG1];
            unless ($heap->{'waiting'}) {
               $heap->{'queue'} ||= [];
               push @{$heap->{'queue'}}, [$event, $msg];
               $debug and print "queue msg for " . $session->ID . "\n";
               return;
            }
            $debug and print "send msg to " . $session->ID . "\n";
            $heap->{'waiting'} = 0;
            my $callback = $heap->{'params'}->{'callback'};
            my $response = "$callback(\"$event\", $msg);";
            $heap->{'client'} and $heap->{'client'}->put(sprintf(
               "%x\r\n%s\r\n0\r\n\r\n", length($response), $response
            )); # FIXME (client is somtimes undef)
            #... do a connection shutdown
            #... if client dont connects in less than 2 seconds
            $heap->{'do_shutdown'} = 1;
            $kernel->delay("do_shutdown", 2);
         },
         "do_shutdown" => sub {
            my ($kernel, $heap) = @_[KERNEL, HEAP];
            $kernel->yield("shutdown") if $heap->{'do_shutdown'};
         },
      },
   );
   POE::Kernel->run;
}
