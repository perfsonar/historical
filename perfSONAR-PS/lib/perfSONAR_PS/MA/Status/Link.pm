package perfSONAR_PS::MA::Status::Link;

sub new {
	my ($package, $link_id, $knowledge, $start_time, $end_time, $oper_status, $admin_status) = @_;

	my %hash = ();

	if (defined $link_id and $link_id ne "") {
		$hash{"ID"} = $link_id;
	}

	if (defined $knowledge and $knowledge ne "") {
		$hash{"KNOWLEDGE"} = $knowledge;
	}
	if (defined $link_id and $link_id ne "") {
		$hash{"START_TIME"} = $start_time;
	}
	if (defined $link_id and $link_id ne "") {
		$hash{"END_TIME"} = $end_time;
	}
	if (defined $link_id and $link_id ne "") {
		$hash{"OPER_STATUS"} = $oper_status;
	}
	if (defined $link_id and $link_id ne "") {
		$hash{"ADMIN_STATUS"} = $admin_status;
	}

	bless \%hash => $package;
}

sub setID($$) {
	my ($self, $id) = @_;

	$self->{ID} = $id;
}

sub setKnowledge($$) {
	my ($self, $knowledge) = @_;

	$self->{KNOWLEDGE} = $knowledge;
}

sub setStartTime($$) {
	my ($self, $starttime) = @_;

	$self->{START_TIME} = $starttime;
}

sub setEndTime($$) {
	my ($self, $endtime) = @_;

	$self->{END_TIME} = $endtime;
}

sub setOperStatus($$) {
	my ($self, $oper_status) = @_;

	$self->{OPER_STATUS} = $oper_status;
}

sub setAdminStatus($$) {
	my ($self, $admin_status) = @_;

	$self->{ADMIN_STATUS} = $admin_status;
}

sub getID($) {
	my ($self) = @_;

	return $self->{ID};
}

sub getKnowledge($) {
	my ($self) = @_;

	return $self->{KNOWLEDGE};
}

sub getStartTime($) {
	my ($self) = @_;

	return $self->{START_TIME};
}

sub getEndTime($) {
	my ($self) = @_;

	return $self->{END_TIME};
}

sub getOperStatus($) {
	my ($self) = @_;

	return $self->{OPER_STATUS};
}

sub getAdminStatus($) {
	my ($self) = @_;

	return $self->{ADMIN_STATUS};
}

1;
