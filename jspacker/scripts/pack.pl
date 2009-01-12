my $version = pop @::argv;
assert((my $ck = $version =~ /^\d[\d\_\w]*$/), 'no version-number defined!');

my $cmd = 'cd ' . app->dir . '/pre-modules/jspacker/scripts/packer; ./jsPacker.pl';

#... create packed files
foreach my $job (@{config('jspacker')->{'jobs'}}) {

   #... collect unpacked files
   my @files = map { app->dir . "/$_" } @{$job->{'src'}};

   #... create dest filename
   my $handler = WebTek::Handler->new;
   my $dest = app->dir . "/" . $job->{'dest'};
   my $compiled = WebTek::Compiler->compile($handler, $dest);
   my $fname = $compiled->($handler, { 'version' => $version });
   print "create packed file '$fname' for:\n";
   
   #... pack files
   my @packed = map {
      #... may render version-number into packed files
      my $compiled = WebTek::Compiler->compile($handler, $_);
      $compiled->($handler, { 'version' => $version });
   } map { print "  - $_\n"; `$cmd -q -i $_` . "\n" } @files;

   #... save packet file
   WebTek::Util::write($fname, @packed);  
   print "\n";

}

