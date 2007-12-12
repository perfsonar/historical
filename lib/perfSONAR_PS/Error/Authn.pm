use perfSONAR_PS::Error::Base;


package perfSONAR_PS::Error::Authn;
use base "perfSONAR_PS::Error::Base";


package perfSONAR_PS::Error::Authn::WrongParams;
use base "perfSONAR_PS::Error::Authn";

package perfSONAR_PS::Error::Authn::AssertionNotIncluded;
use base "perfSONAR_PS::Error::Authn";

package perfSONAR_PS::Error::Authn::AssertionNotValid;
use base "perfSONAR_PS::Error::Authn";

package perfSONAR_PS::Error::Authn::x509NotIncluded;
use base "perfSONAR_PS::Error::Authn";

package perfSONAR_PS::Error::Authn::x509NotValid;
use base "perfSONAR_PS::Error::Authn";

package perfSONAR_PS::Error::Authn::NotSecToken;
use base "perfSONAR_PS::Error::Authn";


1;