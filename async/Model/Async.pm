use WebTek::Util qw( slurp );
use WebTek::Export qw( async );

sub async {
   my %params = @_;
   
   my $deamons = config('async')->{'deamons'};
   my $dir = config('async')->{'dir'};
   
   foreach my $i (1 .. $deamons) {
      my $j = int(rand($deamons)) + 1;
      unless (-d "$dir/$j") {
         mkdir "$dir/$j";
         chmod 0777, "$dir/$j";
      }
      if ($i eq $deamons or not -e "$dir/$j/working") {
         my $last = -e "$dir/$j/last" ? slurp("$dir/$j/last") + 1 : 0;
         WebTek::Util::write("$dir/$j/last", $last);
         WebTek::Util::write("$dir/$j/$last", struct(\%params));
         chmod 0777, "$dir/$j/last";
         chmod 0777, "$dir/$j/$last";
         last;
      }
   }
}
