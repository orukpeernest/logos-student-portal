/* LOGOS student backup validation — preview only.
 * No student data or credentials are sent to the browser database from this module.
 * Actual import must be performed by a privileged server-side RPC after schema verification.
 */
(function(){
  "use strict";
  function trailingFour(reg){
    const digits=String(reg??"").replace(/\D/g,"");
    return digits.length>=4?digits.slice(-4):null;
  }
  function loginFor(student){
    const surname=String(student?.surname??"").trim().toUpperCase();
    const suffix=trailingFour(student?.reg);
    if(!surname||!suffix)return null;
    return surname.replace(/\s+/g,"")+suffix;
  }
  function inspectBackup(payload){
    const students=payload&&Array.isArray(payload.students)?payload.students:null;
    if(!students)return {ok:false,error:"This file is not a supported LOGOS backup: a students array was not found.",total:0,valid:0,invalid:0,duplicateLogins:0,issues:[]};
    if(students.length===0)return {ok:false,error:"This backup contains no student records to import.",total:0,valid:0,invalid:0,duplicateLogins:0,issues:[]};
    const seen=new Map(),issues=[];
    let valid=0;
    students.forEach((student,index)=>{
      const row=index+1,reg=String(student?.reg??"").trim(),surname=String(student?.surname??"").trim(),first=String(student?.first??"").trim();
      const suffix=trailingFour(reg),username=loginFor(student);
      const problems=[];
      if(!reg)problems.push("registration value missing");
      else if(!suffix)problems.push("registration value has fewer than four digits");
      if(!surname)problems.push("surname missing");
      if(!first)problems.push("first name missing");
      if(!student?.id)problems.push("app student ID missing");
      if(username){
        if(seen.has(username)){
          problems.push("duplicate generated username (also row "+seen.get(username)+")");
        }else seen.set(username,row);
      }
      if(problems.length)issues.push({row,problems});
      else valid++;
    });
    const duplicateLogins=issues.filter(x=>x.problems.some(p=>p.startsWith("duplicate generated username"))).length;
    return {ok:issues.length===0,error:null,total:students.length,valid,invalid:issues.length,duplicateLogins,issues};
  }
  function buildImportPayload(payload){
    const report=inspectBackup(payload);
    if(!report.ok)throw new Error("Correct all validation issues before importing student profiles.");
    return payload.students.map(student=>({
      id:String(student.id),
      reg:String(student.reg).trim(),
      surname:String(student.surname).trim(),
      first:String(student.first).trim(),
      other:student.other==null?"":String(student.other),
      phone:student.phone==null?"":String(student.phone),
      gphone:student.gphone==null?"":String(student.gphone),
      gender:student.gender==null?"":String(student.gender),
      dept:student.dept==null?"":String(student.dept),
      exam:student.exam==null?"":String(student.exam),
      fee:student.fee==null?"":String(student.fee),
      added:student.added==null?"":String(student.added),
      start:student.start==null?"":String(student.start),
      cycle:student.cycle??null,
      dbase:student.dbase??null,
      dstart:student.dstart??null,
      expiry:student.expiry??null,
      next:student.next??null
    }));
  }
  window.LOGOSStudentImport={inspectBackup,buildImportPayload};
})();
