
.data					# section declaration

        # Useful offset constants for accessing members of a 
        # struct mp1_blink_struct structure
        LOCATION   = 0    
        ON_CHAR    = 2
        OFF_CHAR   = 3 
        ON_LENGTH  = 4
        OFF_LENGTH = 6
        COUNTDOWN  = 8
        STATUS     = 10
        NEXT       = 12

        STRUCT_SIZE = 16

# Pointer to head of list (initialized to NULL)
mp1_list_head:
        .long   0

.text					# section declaration

# Export the function symbol names

.global mp1_rtc_tasklet
.global mp1_ioctl

# void mp1_poke(void);
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX
mp1_poke:
        
	movl    vmem_base_addr(,1),%edx
	movb    %cl,(%edx,%eax,1)
	ret
#mp1_rtc_tasklet
# Interface: Register-based arguments (C-style)
#    Inputs: None
#   Outputs: Text-mode fish animation
# Registers: None
mp1_rtc_tasklet:
        pushl %ebp       
        movl  %esp, %ebp 
        pushl %ebx       
        pushl %esi       
        pushl %edi       
        movl mp1_list_head, %edi #  edi store linked list head address
  tl_initial:
        cmpl $0, %edi             #check null  
        je tl_done           

        subw $1,COUNTDOWN(%edi)               
        cmpw $0,COUNTDOWN(%edi)               
        jne tl_next                           

        movzwl  LOCATION(%edi),%eax           #prepare for poke call
        shll  $1,%eax     

        cmpw $0,STATUS(%edi)                  
        je tl_offchar

        movb OFF_CHAR(%edi),%cl               # poke with off char when status=1
        call mp1_poke                        
       
        movw OFF_LENGTH(%edi),%dx             #update
        movw %dx,COUNTDOWN(%edi)              
        movw $0,STATUS(%edi)                  
        
        jmp tl_next                           
  tl_offchar:
        movb  ON_CHAR(%edi),%cl               # poke with on char when status=1
        call  mp1_poke                        
        
        movw ON_LENGTH(%edi),%dx              #update  
        movw %dx,COUNTDOWN(%edi)              
        movw $1,STATUS(%edi)                  
  tl_next:
        movl NEXT(%edi),%edi                  
        jmp tl_initial    
  tl_done:
        popl %edi        
        popl %esi       
        popl %ebx       
        leave
    ret

mp1_ioctl:

        cmpl $3,8(%esp) # check if larger than 3

        ja  cmd_err    

        movl 8(%esp), %edx # pass cmd number to edx

        jmp *operation(,%edx,4)

  cmd_err:  
        movl $-1, %eax
    ret
# Interface: Register-based arguments (C-style)
#    Inputs: A pointer points to the struct which needs to be added
#   Outputs: Text-mode fish (fixed frame)
# Registers: EBX,EDI
mp1_ioctl_add:
        pushl %ebp       
        movl  %esp, %ebp 
        pushl %ebx       
        pushl %esi       
        pushl %edi       
        movl 8(%ebp),%ebx   # ebx store arg (user ptr)

        cmpl  $0,%ebx      
        je add_arg_err      #(no need to free memory)

        pushl $STRUCT_SIZE 
        call mp1_malloc
        addl  $4,%esp      

        cmpl  $0,%eax       
        je add_err          #check malloc error

        movl  %eax,%edi     # edi store dest ptr
        pushl $STRUCT_SIZE  
        pushl %ebx          #push arguments for copy from user function call
        pushl %edi         
        call mp1_copy_from_user
        addl  $12,%esp               

        cmpl  $0, %eax               
        jne   add_err

        cmpw  $1999,LOCATION(%edi) 
        ja    add_err

        movw  ON_LENGTH(%edi),%dx             #copy       
        movw  %dx,COUNTDOWN(%edi)              
        movw  $1,STATUS(%edi)                 
        movl  mp1_list_head,%edx              
        movl  %edx,NEXT(%edi)                 
        movl  %edi,mp1_list_head            

        movzwl  LOCATION(%edi),%eax           #prepare for poke
        shll  $1,%eax                         
        movb  ON_CHAR(%edi),%cl               
        call  mp1_poke                        
        jmp add_done
  add_err: 
        pushl %edi                      
        call mp1_free                   
        addl $4,%esp                  
  add_arg_err:
        movl $-1,%eax
  add_done:
        popl %edi
        popl %esi
        popl %ebx
        leave
	ret
# Interface: Register-based arguments (C-style)
#    Inputs: The LOCATION needs to be removed
#   Outputs: Text-mode animation with M disappeared
# Registers: EAX,EDI,EBX,ESI        
mp1_ioctl_remove:
        pushl %ebp        
        movl  %esp, %ebp  
        pushl %ebx       
        pushl %esi       
        pushl %edi
        movl 8(%ebp),%ebx        #ebx stor location of the struct
        movl mp1_list_head, %edi 

        pushl %ebx               #ebx stores the LOCATION that needs a mp1_search call
        call mp1_search         
        addl $4, %esp

        cmpl $-1,%eax
        je rm_err
        cmpl $1,%eax
        jne rm_norm

        movl NEXT(%edi),%esi      #remove linked list head
        movl %esi,mp1_list_head  
        jmp rm_free
  rm_norm:
        movl NEXT(%eax),%edi
        movl NEXT(%edi),%esi
        movl %esi,NEXT(%eax)
  rm_free:
        pushl %edi                     
        call mp1_free                   
        addl $4,%esp                  
        jmp rm_done                       
  rm_err:
        movl $-1, %eax
  rm_done:
        popl %edi
        popl %esi
        popl %ebx
        leave 
    ret
# Interface: Register-based arguments (C-style)
#    Inputs: A pointer points to the struct which needs to be found from the linked list
#   Outputs: none
# Registers: EAX,EBX,EDI    
mp1_ioctl_find:
        pushl %ebp        
        movl  %esp, %ebp 
        pushl %ebx       
        pushl %esi      
        pushl %edi
        movl 8(%ebp),%ebx   #ebx store arg (user ptr) 

        cmpl  $0,%ebx       
        je find_err     

        movl mp1_list_head, %edi 
        movzwl LOCATION(%ebx), %eax  #eax stores the LOCATION that needs a mp1_search call

        pushl %eax
        call mp1_search
        addl $4, %esp

        cmpl $-1,%eax
        je find_err
        cmpl $1,%eax
        je find_found

        movl NEXT(%eax),%edi         #eax has the address of struct previous to what need to be found
  find_found:
        pushl $STRUCT_SIZE
        pushl %edi
        pushl %ebx
        call mp1_copy_to_user
        addl $12, %esp
        cmpl $0, %eax
       je find_done
  find_err:
        movl $-1, %eax
  find_done:
        popl %edi
        popl %esi
        popl %ebx
        leave
	ret
# Interface: Register-based arguments (C-style)
#    Inputs: Two locations: 1st 2 bytes: location that will be synced to,2nd 2 bytes: location that will be synced with.
#   Outputs: I/M blink at the same rate with rest animation
# Registers: ESI,EDI,EBX,EDX
mp1_ioctl_sync:
        pushl %ebp        
        movl  %esp, %ebp  
        pushl %ebx       
        pushl %esi       
        pushl %edi
        movzwl 10(%ebp), %esi  # esi store zero exended 1st arg

        pushl %esi
        call mp1_search
        addl $4, %esp

        cmpl $-1,%eax
        je sync_err
        cmpl $1,%eax
        jne  sync_norm1

        movl mp1_list_head, %edi #
        jmp sync_head1           #
  sync_norm1:                    #edi has address of 1st LOCATION found
        movl NEXT(%eax), %edi    # 
  sync_head1:
        movzwl 8(%ebp), %ebx # esi store zero exended 2nd arg
        pushl %ebx
        call mp1_search
        addl $4, %esp

        cmpl $-1,%eax
        je sync_err
        cmpl $1,%eax
        jne  sync_norm2

        movl mp1_list_head, %edx #
        jmp sync_head2           #
  sync_norm2:                    #edx has address of 2nd LOCATION found
        movl NEXT(%eax), %edx    # 
  sync_head2:
        movw ON_LENGTH(%edi),%si   #update
        movw %si,ON_LENGTH(%edx)
        movw OFF_LENGTH(%edi),%si
        movw %si,OFF_LENGTH(%edx)
        movw COUNTDOWN(%edi),%si
        movw %si,COUNTDOWN(%edx)
        movw STATUS(%edi),%si
        movw %si,STATUS(%edx)

        cmpw $0,%si
        je sync_off
        movb  ON_CHAR(%edx),%cl               
        jmp sync_do
  sync_off:
        movb  OFF_CHAR(%edx),%cl               
  sync_do:
        movzwl  LOCATION(%edx),%eax           
        shll  $1,%eax                         
        call  mp1_poke                        
        jmp sync_done
  sync_err:
        movl $-1, %eax
  sync_done:
        popl %edi
        popl %esi
        popl %ebx
        leave
	ret
# Interface: Register-based arguments (C-style)
#    Inputs: LOCATION the needs to be found
#   Outputs: eax:-1 when not found, 1 when found at head, previous sturct address for other cases
# Registers: ESI,EDI,EAX
mp1_search:
        pushl %ebp        
        movl  %esp, %ebp  
        pushl %ebx       
        pushl %esi       
        pushl %edi      
        movl 8(%ebp), %esi
        movl mp1_list_head, %edi #  edi store linked list head address
        cmpl $0, %edi      
        je search_err
        cmpw %si,LOCATION(%edi)
        je search_head

  search_initial:                       #traverse
        cmpl $0, %edi      
        je search_err
        cmpw %si,LOCATION(%edi)
        je search_found    
  search_next:
        movl %edi,%eax                  #eax store prev add
        movl NEXT(%edi),%edi             
        jmp search_initial              
        
  search_found:
        jmp search_done
  search_head:
        movl $1,%eax               
        jmp search_done     
  search_err:
        movl $-1,%eax               
  search_done:
        popl %edi
        popl %esi
        popl %ebx
        leave
    ret
operation:
.long mp1_ioctl_add, mp1_ioctl_remove, mp1_ioctl_find, mp1_ioctl_sync

.end
