(* le type des instructions de la VM *)
type instr = I_GALLOC of unit 
           | I_GSTORE of ptr
           | I_GFETCH of ptr
           | I_STORE of ptr
           | I_FETCH of ptr
           | I_PUSH of value
           | I_PUSH_FUN of ptr
           | I_POP of unit
           | I_CALL of long (* arity *)
           | I_RETURN of unit
           | I_JUMP of ptr
           | I_JTRUE of ptr
           | I_JFALSE of ptr

(* l'état de la VM comprend (dans l'ordre) :
   - un bloc d'activation
   - un pointeur [gp] sur la prochaine variable globale à allouer
   - un pointeur [hp] sur la prochaine adresse libre dans le tas
   - un buffer d'écriture postée [write_buf],comportement un booléen 
        (qui indique quand une écriture doit avoir lieu), 
        une adresse à écrire et la nouvelle valeur.
   - un booléen [finished] qui passe à vrai à la fin de l'exécution,
     en particulier lors de l'exécution d'une instruction POP
     sur une pile de 1 élément. *)

type vm_state = (frame * ptr * ptr * (bool * (ptr * value)) * bool);; 


let print_vm_state ((frame,gp,hp,_,_):vm_state) : unit =
  print_frame frame;
  print_string "|gp:"; print_int gp;
  print_string "|hp:"; print_int gp;
  print_newline();;
  
(* exécution d'une instruction du programme, le [pc] 
   courrant est dans l'état de la VM (state) *)
let vm_run_instr (state : vm_state) : vm_state =
  let (frame,gp,hp,wg,finished) = state in
  let (sp,env,pc,fp) = frame in
  let instr = code.(pc) in
  match instr with
  | I_GALLOC ()->((sp, env, pc, fp), gp+1, hp, wg, finished)

  | I_GSTORE i -> globals.(i) <- stack.(sp-1);
                    let temp = sp - 1 in
                    ((temp, env, pc,fp),gp,hp,wg,finished)

  | I_GFETCH i -> stack.(sp) <- globals.(i);
                  ((sp+1, env, pc, fp), gp, hp, wg, finished)
  | I_PUSH v -> stack.(sp) <- v;
                ((sp+1, env, pc, fp), gp, hp, wg, finished)

  | I_POP () -> if (sp - 1 = 0) then
                (print_value(stack.(sp-1)); 
                ((sp-1, env, pc, fp), gp, hp, wg, true))
                else
                ((sp-1, env, pc, fp), gp, hp, wg, finished)
  
  | I_JUMP l -> ((sp, env, l - 1, fp), gp, hp, wg, finished) 
  
  | I_FETCH i ->  let temp = heap.(env+i) in 
                  stack.(sp) <- temp; 
                  ((sp + 1, env, pc, fp), gp, hp, wg, finished)         

  | I_RETURN () -> let (n_sp, n_env, n_pc, n_fp) = frames.(fp-1) in
                    stack.(n_sp) <- stack.(sp - 1);
                    ((n_sp + 1, n_env, n_pc, n_fp), gp, hp, wg, finished)
                      
  | I_PUSH_FUN l -> stack.(sp) <- Fermeture (l,env); 
                    ((sp + 1, env, pc, fp), gp, hp, wg, finished)
  

  | I_STORE i -> let var = stack.(sp-1) in
                  heap.(env+i) <- var;
                  ((sp-1, env, pc, fp), gp, hp, wg, finished)
                  
  | I_JTRUE l ->let var = stack.(sp-1) in
                        let jtrue = match var with
                                        | Bool(x)  -> x
                                        | _ -> false
                                        end
                        in
                        let temp = if jtrue then l - 1 else pc in
                        ((sp-1, env, temp, fp), gp, hp, wg, finished)

  | I_JFALSE l -> let var = stack.(sp-1) in
                  let jfalse = match var with
                                  | Bool (x) -> x
                                  | _ -> false
                                  end
                  in
                  let temp = if jfalse then pc else l - 1 in
                  ((sp-1, env, temp, fp), gp, hp, wg, finished)


  | I_CALL (n) -> let value = stack.(sp - 1) in
      match value with
      | Prim (p) -> match p with 
        | P_ADD () -> let rec add(args,final) = if args = 0 then final 
                                              else let var = stack.(sp - 1 - args) in 
                                              let addition = match var with 
                                                  | Int a -> a 
                                                  | _ -> fatal_error "NON INT "
                                                  end 
                                                in 
                                                add (args-1, final+addition)
                                              in 
            
            let res = add(n,0) in
            stack.(sp-n-1) <- Int res;
            ((sp - n, env, pc, fp), gp, hp, wg, finished)
        
        | P_SUB () -> if n < 2 then fatal_error "Min 2 args" 
                      else (
                      let rec sub(args,final) = if args = 0 then final 
                      else let var = stack.(sp - 1 - args) in 
                      let sous = match var with 
                          | Int a -> a 
                          | _ -> fatal_error "NON INT"
                          end 
                        in 
                        sub(args-1, final-sous)
                      in 
                      let valeur_depart = match stack.(sp - n - 1) with 
                                          | Int a -> a 
                                          | _ -> fatal_error "NON INT" 
                      end in
                      let resultat = sub (n - 1, valeur_depart) in
                      let val_absolue = if resultat < 0 then resultat * (-1) else resultat in
                      stack.(sp - n - 1) <- Int val_absolue;
                      ((sp - n, env, pc, fp), gp, hp, wg, finished))


        | P_MUL () -> let rec mul(args,final) = if args = 0 then final 
                                              else let var = stack.(sp - 1 - args) in 
                                              let mult = match var with 
                                                  | Int a -> a 
                                                  | _ -> fatal_error "NON INT"
                                                  end 
                                                in 
                                                mul(args-1,final * mult) 
                                                      in 
                      let res = mul(n,1) in
                      stack.(sp-n-1) <- Int res;
                    ((sp - n, env, pc, fp), gp, hp, wg, finished)


        | P_DIV () -> if n < 1 then fatal_error "Min 2 args"
                      else
                      let rec div (args, final) = 
                          if args = 0 then final 
                          else 
                              let divisor = match stack.(sp - 1 - args) with 
                                |Int a -> a 
                                | _ -> fatal_error "NON INT"
                              end in
                              if divisor = 0 then fatal_error "Div par zero impossible"
                              else div (args - 1, final / divisor)
                      in
                      let valeur_depart = match (stack.(sp - n - 1)) with 
                      |Int a -> a 
                      | _ -> fatal_error "NON INT" 
                      end in
                      let res = div (n - 1, valeur_depart) in
                      stack.(sp - n - 1) <- Int res; 
                      ((sp - n, env, pc, fp), gp, hp, wg, finished)

        | P_POW () -> 
          if n != 2 then fatal_error "Exact 2 args"
          else
              let i = match stack.(sp - 3) with 
                |Int a -> a 
                | _ -> fatal_error "NON INT" 
              end in
              let puissance = match stack.(sp-2) with 
                |Int a -> a 
                | _ -> fatal_error "NON INT" 
              end in
              let rec pow (j, puis, final) =
                  if puis = 0 then final
                  else pow (j, puis - 1, final * j)
              in
              let res = pow (i, puissance, 1) in
              stack.(sp - n - 1) <- Int res;
              ((sp - n, env, pc, fp), gp, hp, wg, finished)
        
        | P_LT () -> 
          if n != 2 then fatal_error "Exact 2 args"
          else
              let a = match stack.(sp - 3) with 
                |Int a -> a 
                | _ -> fatal_error "NON INT" 
              end in
              let b = match stack.(sp - 2) with 
                |Int a -> a 
                | _ -> fatal_error "NON INT" 
              end in
              let res = a > b in
              stack.(sp - n - 1) <- Bool res; 
              ((sp - n, env, pc, fp), gp, hp, wg, finished)

        | P_EQ () -> 
          if n != 2 then fatal_error "Exact 2 args"
          else
            let e1 = stack.(sp-2) in 
            let e2 = stack.(sp-3) in 
            let verif =
              match e1 with
              | Int(a) -> match e2 with 
                  |Int(b) -> a = b 
                  | _ -> print_string "Les 2 sont pas INT\n" ; exit () 
                end
              | Bool(a1) -> match e2 with 
                  Bool(b2) -> if a1 then (if b2 then true else false) else (if b2 then false else true) 
                  | _ -> print_string "Les 2 sont pas BOOL\n" ; exit () 
                end
              | Nil () -> match e2 with 
                  Nil () -> true 
                  | _ -> print_string "Pas pareil\n" ; exit () 
                end
              | _ ->  print_string "Erreur \n" ; exit () 
            end
            in stack.(sp-1-n ) <- Bool verif;
            ((sp-n, env, pc, fp),gp ,hp,wg,finished)
        
          | _ -> state
        end
        | Fermeture (l,env_sp) -> 
          let new_env  = hp in
          let new_hp = hp+n+1 in 
          heap.(new_hp-1) <- Int env;
          let rec sauv(args, sp1, env1) =
            if args = 0 then sp1
            else(
                heap.(env) <- stack.(sp - args - 1);
                sauv(args - 1, sp1, env1 +1)
              )
          in
          let new_sp = copy_args_to_heap (n, sp, new_env)
          in
          frames.(fp) <- (sp-n-1, env, pc, fp);
          let new_fp = fp + 1 in
          frames.(new_fp)<-(sp-n-1 , env_sp , pc, fp);
          ((sp-n-1 , new_env , l - 1, new_fp), gp, new_hp , wg, finished)
      | _ -> state 
    end
          
  | _ -> print_string "Instr inconnu\n";exit ()
  end;;
  

(* exécution d'un programme (stocké dans le tableau global [bytecode] *)
let rec vm_run_code ((state,debug) : vm_state * bool) : unit =
  
  (if debug then print_vm_state state else ()); (* affichage de l'état de la VM *)
  
  let (frame,gp,hp,write_buf,finished) = vm_run_instr(state) in
  
  if finished then () else 
  let (sp,env,pc,fp) = frame in
  let next_pc = pc+1 in
  (* fait [pc+1] après chaque instruction exécutée : 
     en cas de changement de pc par l'instruction d'avant (branchements, etc.), 
     il faudra vers [nouveau_pc-1]) *)
  vm_run_code(((sp,env,next_pc,fp),gp,hp,write_buf,finished),debug) ;; 