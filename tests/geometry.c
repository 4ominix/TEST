#include <assert.h>
#include <stdio.h>
#include "../Core/ICGeometry.h"
static void near(double a,double b){assert(fabs(a-b)<1e-8);}
int main(void){
    ICMatrix m=ICGeometry(100,100,200,400,0,0,0,1,0,0);
    near(m.a,2);near(m.d,2);near(m.tx,0);near(m.ty,100);
    m=ICGeometry(100,100,200,400,0,0,1,1,0,0);near(m.a,4);near(m.tx,-100);near(m.ty,0);
    m=ICGeometry(100,200,400,200,90,0,0,1,0,0);near(m.a,0);near(m.b,-2);near(m.c,2);near(m.tx,0);near(m.ty,200);
    m=ICGeometry(100,200,400,200,270,0,0,1,0,0);near(m.b,2);near(m.c,-2);near(m.tx,400);near(m.ty,0);
    m=ICGeometry(100,100,100,100,180,0,0,1,0,0);near(m.a,-1);near(m.d,-1);near(m.tx,100);near(m.ty,100);
    m=ICGeometry(100,100,100,100,0,1,0,1,.1,.2);near(m.a,-1);near(m.tx,105);near(m.ty,-10);
    m=ICGeometry(100,200,400,200,90,1,0,1,0,0);near(m.b,-2);near(m.c,-2);near(m.tx,400);near(m.ty,200);
    m=ICGeometry(100,100,100,100,0,0,0,2,0,0);near(m.a,2);near(m.tx,-50);
    m=ICGeometry(0,100,100,100,0,0,0,1,0,0);near(m.a,0);near(m.b,0);
    m=ICGeometry(NAN,100,100,100,0,0,0,1,0,0);near(m.a,0);
    m=ICGeometry(100,100,100,100,0,0,0,INFINITY,NAN,INFINITY);near(m.a,1);near(m.tx,0);near(m.ty,0);
    m=ICGeometry(100,100,100,100,-90,0,0,1,0,0);near(m.b,1);near(m.c,-1);
    m=ICGeometry(100,100,100,100,450,0,0,1,0,0);near(m.b,-1);near(m.c,1);
    m=ICGeometry(100,100,100,100,0,0,0,100,100,-100);near(m.a,8);near(m.tx,-250);near(m.ty,-250);
    puts("PASS: geometry Fit/Fill, all rotations, output mirror, pan, zoom and invalid inputs");return 0;
}
