#include<stdio.h>
#include<stdlib.h>
#include<string.h>

int main(){
    int *ptr,i=0;
    while (1) {
        ptr=(int*)malloc(10000000);  // 10mb
        if(ptr==NULL)
        {
            printf("Sorry! unable to allocate memory");
            exit(1);
        }
        memset(ptr, '.', 10000000);
        i++;
        printf("%dmb\n", i*10);
        sleep(1);
    }
}
