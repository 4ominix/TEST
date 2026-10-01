#include <assert.h>
#include <stdio.h>
#include "../Core/ICRequests.h"
int main(void) {
    ICRequest slots[3];
    for(int i=0;i<3;i++){slots[i].width=0;slots[i].height=0;slots[i].format=0;slots[i].time=0;}
    ICRecordRequest(slots,1584,1188,1,10);
    ICRecordRequest(slots,1080,1440,1,10.01);
    assert(slots[0].width==1584 && slots[1].width==1080);
    ICRecordRequest(slots,1584,1188,1,10.02);
    assert(slots[0].time==10.02 && slots[1].width==1080 && slots[2].width==0);
    ICRecordRequest(slots,1080,1440,2,10.03);
    assert(slots[2].format==2 && slots[1].format==1);
    assert(ICRequestLive(slots[0],10.04) && ICRequestLive(slots[1],10.04));
    assert(!ICRequestLive(slots[0],12.03));
    assert(!ICRequestLive(slots[0],9));
    ICRecordRequest(slots,640,480,3,10.04);
    assert(slots[0].width==1584 && slots[1].width==640 && slots[2].format==2);
    ICRecordRequest(slots,0,0,1,10.1);
    assert(slots[1].width==640);
    ICRecordRequest(slots,1,1,1,NAN);
    assert(slots[1].width==640);
    assert(!ICRequestLive(slots[1],NAN));
    puts("PASS: bounded multi-output requests, distinct formats, LRU, expiry and invalid input");return 0;
}
