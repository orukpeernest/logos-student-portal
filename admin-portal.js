/* LOGOS Admin portal: staging-only public key; privileged actions remain RPC-gated. */
const ADMIN_CONFIG=window.LOGOS_SUPABASE_CONFIG;
const ADMIN_STAGING_URL="https://rxuusshnsrpegwwktvii.supabase.co";
if(!window.supabase||ADMIN_CONFIG?.url!==ADMIN_STAGING_URL||!ADMIN_CONFIG?.publishableKey?.startsWith("sb_publishable_")){
  const panel=document.getElementById("admin-login");
  if(panel)panel.textContent="Admin portal configuration is missing or does not target the approved staging project.";
  throw new Error("LOGOS admin portal stopped: valid staging configuration is required.");
}
const adminSb=window.supabase.createClient(ADMIN_CONFIG.url,ADMIN_CONFIG.publishableKey);
const admin$=id=>document.getElementById(id),loginPanel=admin$("admin-login"),adminApp=admin$("admin-app"),adminToast=admin$("admin-toast");
function adminMsg(message){adminToast.textContent=message;adminToast.style.display="block";setTimeout(()=>adminToast.style.display="none",4500)}
function setAdminStatus(message){admin$("admin-message").textContent=message}
async function adminRpc(name,args={}){const {data,error}=await adminSb.rpc(name,args);if(error)throw error;return data}
function showAdmin(){loginPanel.classList.add("hidden");adminApp.classList.remove("hidden");admin$("admin-signout").classList.remove("hidden")}
function showLogin(){loginPanel.classList.remove("hidden");adminApp.classList.add("hidden");admin$("admin-signout").classList.add("hidden")}
let adminVerificationToken=0;
async function verifyAdmin(user){const token=++adminVerificationToken;try{const allowed=await adminRpc("is_logos_admin");if(token!==adminVerificationToken)return;if(allowed!==true)throw new Error("Your account is not authorized as a LOGOS administrator.");showAdmin();admin$("admin-status").textContent=user?.email||"Authorized admin";setAdminStatus("Administrator permission verified. Actions are checked by Supabase.");}catch(e){if(token!==adminVerificationToken)return;await adminSb.auth.signOut();showLogin();adminMsg(e.message||"Admin verification failed.")}}
admin$("admin-login-form").onsubmit=async e=>{e.preventDefault();const button=admin$("admin-login-btn");button.disabled=true;try{const {data,error}=await adminSb.auth.signInWithPassword({email:admin$("admin-email").value.trim(),password:admin$("admin-password").value});if(error)throw error;setAdminStatus("Checking administrator access…")}catch(err){adminMsg(err.message||"Sign-in failed.")}finally{button.disabled=false}};

admin$("save-question").onsubmit=async e=>{e.preventDefault();const f=new FormData(e.target),image=String(f.get("image_url")||"").trim();if(image&&!image.startsWith("https://")){adminMsg("Question image URL must use HTTPS.");return}const q={subject:String(f.get("subject")).trim(),topic:String(f.get("topic")||"").trim(),exam_type:String(f.get("exam_type")||"").trim(),exam_year:f.get("exam_year")?Number(f.get("exam_year")):null,question_text:String(f.get("question_text")).trim(),option_a:String(f.get("option_a")).trim(),option_b:String(f.get("option_b")).trim(),option_c:String(f.get("option_c")).trim(),option_d:String(f.get("option_d")).trim(),correct_answer:String(f.get("correct_answer")).trim().toUpperCase(),explanation:String(f.get("explanation")||"").trim(),image_url:image||null,is_practice:f.get("is_practice")==="true"};const id=String(f.get("id")||"").trim();if(id)q.id=id;try{const data=await adminRpc("logos_td_admin_save_question",{p_question:q});admin$("saved-question").textContent=JSON.stringify(data,null,2);setAdminStatus("Question saved. Returned data may contain its ID.");adminMsg("Question saved.")}catch(err){adminMsg(err.message||"Save question failed.")}};

admin$("exam-status").onsubmit=async e=>{e.preventDefault();const f=new FormData(e.target);try{const data=await adminRpc("logos_td_admin_set_exam_status",{p_exam_id:String(f.get("exam_id")).trim(),p_status:String(f.get("status")).trim()});setAdminStatus("Exam status response: "+JSON.stringify(data));adminMsg("Status update response received.")}catch(err){adminMsg(err.message||"Status update failed.")}};

admin$("assessment-upload-form").onsubmit=async e=>{
  e.preventDefault();
  const form=e.currentTarget,fields=new FormData(form),file=admin$("assessment-question-file").files?.[0];
  const result=admin$("assessment-upload-result"),button=admin$("assessment-upload-submit");
  if(!file){result.textContent="Choose the assessment question JSON file first.";return}
  if(file.size>10*1024*1024){result.textContent="The question file exceeds the 10 MB limit.";return}
  button.disabled=true;result.textContent="Validating the assessment question file…";
  let questions;
  try{
    if(!window.LOGOSTestQuestionImport)throw new Error("Test question upload validator did not load.");
    questions=window.LOGOSTestQuestionImport.parse(await file.text(),String(fields.get("subject")).trim());
    if(questions.length>500)throw new Error("A single assessment upload is limited to 500 questions.");
  }catch(err){result.textContent=err.message||"Question file validation failed.";button.disabled=false;return}
  let examId="",attached=0;
  try{
    result.textContent="Creating a locked draft assessment…";
    const exam=await adminRpc("logos_td_admin_create_exam",{
      p_title:String(fields.get("title")).trim(),
      p_subject:String(fields.get("subject")).trim(),
      p_exam_type:String(fields.get("assessment_period")).trim(),
      p_duration_minutes:Number(fields.get("duration_minutes"))
    });
    const findId=value=>{
      if(typeof value==="string")return value;
      if(Array.isArray(value))return findId(value[0]);
      if(value&&typeof value==="object"){
        for(const key of ["id","exam_id","question_id"])if(value[key]!==undefined&&value[key]!==null)return String(value[key]);
        for(const key of ["data","result","exam","question"])if(value[key]!==undefined){const found=findId(value[key]);if(found)return found}
      }
      return "";
    };
    examId=findId(exam);
    if(!examId)throw new Error("The draft was created but its exam ID was not returned. No questions were uploaded.");
    const toIso=value=>value?new Date(value).toISOString():null;
    const startsAt=toIso(String(fields.get("starts_at")||""));
    const endsAt=toIso(String(fields.get("ends_at")||""));
    if(startsAt&&endsAt&&new Date(endsAt)<=new Date(startsAt))throw new Error("Assessment closing time must be after its start time.");
    await adminRpc("logos_td_admin_configure_exam",{
      p_exam_id:examId,
      p_academic_session:String(fields.get("academic_session")||"").trim(),
      p_starts_at:startsAt,
      p_ends_at:endsAt,
      p_max_attempts:Number(fields.get("max_attempts")||1)
    });
    result.textContent="Uploading all "+questions.length+" test-only questions in one database transaction…";
    const uploadPayload=questions.map(question=>({
      ...question,
      exam_type:question.exam_type||String(fields.get("assessment_period")).trim(),
      is_practice:false
    }));
    const uploadResult=await adminRpc("logos_td_admin_bulk_upload_exam_questions",{
      p_exam_id:examId,
      p_questions:uploadPayload
    });
    attached=Number(uploadResult?.question_count)||0;
    if(attached!==questions.length)throw new Error("The database did not confirm the complete question upload. Keep the assessment as a draft.");
    result.textContent="Draft saved successfully. "+attached+" test-only questions attached atomically. Students cannot access this assessment until you release it. Draft exam ID: "+examId;
    setAdminStatus("Draft assessment created with "+attached+" uploaded test questions. It has not been released.");
    adminMsg("Draft assessment and questions saved.");
    form.reset();
  }catch(err){
    const partial=examId?" Draft exam ID: "+examId+". The atomic upload did not complete; no partial question batch was committed. Keep the draft unreleased.":"";
    result.textContent=(err.message||"Assessment upload failed.")+partial;
    setAdminStatus("Assessment upload did not finish. Do not release the draft until it has been checked.");
    adminMsg("Assessment upload incomplete.");
  }finally{button.disabled=false}
};

admin$("exam-results-release").onsubmit=async e=>{
  e.preventDefault();
  const f=new FormData(e.currentTarget);
  try{
    const data=await adminRpc("logos_td_admin_set_results_released",{
      p_exam_id:String(f.get("exam_id")).trim(),
      p_released:String(f.get("released"))==="true"
    });
    setAdminStatus("Results visibility updated: "+JSON.stringify(data));
    adminMsg("Results visibility updated.");
  }catch(err){adminMsg(err.message||"Unable to update results visibility.")}
};
admin$("delete-question").onsubmit=async e=>{e.preventDefault();const f=new FormData(e.target),id=String(f.get("question_id")).trim();if(!confirm("Delete question "+id+"? This action cannot be undone."))return;try{const ok=await adminRpc("logos_td_admin_delete_question",{p_question_id:id});setAdminStatus("Delete response: "+JSON.stringify(ok));adminMsg(ok?"Question deleted.":"Deletion was not confirmed.")}catch(err){adminMsg(err.message||"Delete failed.")}};
admin$("student-backup-form").onsubmit=async e=>{
  e.preventDefault();
  const file=admin$("student-backup-file").files?.[0],result=admin$("student-backup-result"),button=admin$("student-backup-check");
  if(!file){result.textContent="Choose a JSON backup file first.";return}
  if(file.size>20*1024*1024){result.textContent="The selected file is larger than the 20 MB validation limit.";return}
  button.disabled=true;result.textContent="Reading and validating backup…";
  try{
    const payload=JSON.parse(await file.text());
    if(!window.LOGOSStudentImport)throw new Error("Student backup validator did not load.");
    const report=window.LOGOSStudentImport.inspectBackup(payload);
    if(!report.error){
      const lines=["Backup structure: "+(report.ok?"valid":"needs correction"),"Student records found: "+report.total,"Records passing checks: "+report.valid,"Records with issues: "+report.invalid,"Duplicate generated usernames: "+report.duplicateLogins];
      report.issues.slice(0,8).forEach(issue=>lines.push("Row "+issue.row+": "+issue.problems.join("; ")));
      if(report.issues.length>8)lines.push("…and "+(report.issues.length-8)+" more row(s) with issues.");
      lines.push("No records have been uploaded or changed. Server-side import is a separate step.");
      result.textContent=lines.join("\n");
    }else result.textContent=report.error;
  }catch(err){result.textContent=err instanceof SyntaxError?"The selected file is not valid JSON.":(err.message||"Backup validation failed.")}
  finally{button.disabled=false}
};
admin$("admin-signout").onclick=async()=>{await adminSb.auth.signOut();showLogin()};
(async()=>{const {data}=await adminSb.auth.getSession();if(data.session)await verifyAdmin(data.session.user);else showLogin();adminSb.auth.onAuthStateChange((event,session)=>{if(session)verifyAdmin(session.user);else{adminVerificationToken++;showLogin()}})})();