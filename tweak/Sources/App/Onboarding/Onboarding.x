#import "Core/SGCore.h"
#import "Onboarding.h"

%ctor {
    SGSetEnabled(SGKeyOnboardingSeen, YES);
    if (SGRedesignAvailable()) SGSetEnabled(SGKeyRedesign, YES);
}
