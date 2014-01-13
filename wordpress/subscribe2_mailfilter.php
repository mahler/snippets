 <?php 
add_filter('s2_registered_subscribers', function($registered, $args) { 
	// $registered is an array with email addresses
	$activeUsers = new Array();

	foreach ($registered as $registeredEmail) { 
		// Find the current user role
		$theUser = get_user_by( 'email', $registeredEmail );
		$theUserRoles = $theUser->roles;
		$userRole = array_shift($theUserRoles);

		// If the user does not have a role, do not send email.
		if (!empty($userRole )) {
			array_push($activeUsers, $registeredEmail);
		}
	}

	return $activeUsers;
}) 
?>

