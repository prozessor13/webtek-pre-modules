
sub comet_connection :Macro
   :Param(event="event1" comma separated list of events listen for)
   :Param(callback="js-function-name" javascript callback function, this function takes 2 arguments event and obj)
{
   my ($self, %params) = @_;
   
   $params{'port'} = config('comet')->{'emitter'}->{'port'};
   $params{'location'} ||= config('comet')->{'emitter'}->{'location'};
   $params{'event'} = join "/", map {
      /\./ ? $_ : app->name . ".$_"
   } split ",", $params{'event'};
   return $self->render_template("/others/comet", \%params);
}
