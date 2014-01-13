 <?php 
add_filter('s2_registered_subscribers', function($registered, $args) { 
	// $registered er et array med email adresser
	$activeUsers = new Array();

	// Løb listen af mail-modtagere igennem...
	foreach ($registered as $registeredEmail) { 
		// Find denne brugers rolle i forhold til sitet.
		$theUser = get_user_by( 'email', $registeredEmail );
		$theUserRoles = $theUser->roles;
		$userRole = array_shift($theUserRoles);

		// Hvis brugeren ikke har en rolle, vil vi ikke håndtere vedkommende, men hvis de har en (admin, editor, author, ...), så skal de have mailen.
		if (!empty($userRole )) {
			array_push($activeUsers, $registeredEmail);
		}
	}

	return $activeUsers;
}) 
?>

