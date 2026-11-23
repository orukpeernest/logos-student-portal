/* LOGOS Test Driller assessment-question file parser.
 * Test uploads are always normalized as exam-only questions; they never enter Practice.
 */
(function(root){
  "use strict";
  const LETTERS=["A","B","C","D"];
  function clean(value){return value===undefined||value===null?"":String(value).trim()}
  function normalizeQuestion(raw,index,defaultSubject){
    if(!raw||typeof raw!=="object"||Array.isArray(raw))throw new Error("Question "+(index+1)+" must be an object.");
    const questionText=clean(raw.question_text??raw.question??raw.text);
    if(!questionText)throw new Error("Question "+(index+1)+" is missing its question text.");
    const rawOptions=raw.options;
    const options={};
    LETTERS.forEach(letter=>{
      const lower=letter.toLowerCase();
      let value=raw["option_"+lower]??raw["option"+letter]??raw[letter];
      if(value===undefined&&Array.isArray(rawOptions))value=rawOptions[LETTERS.indexOf(letter)];
      if(value===undefined&&rawOptions&&typeof rawOptions==="object")value=rawOptions[letter]??rawOptions[lower];
      options[letter]=clean(value);
      if(!options[letter])throw new Error("Question "+(index+1)+" is missing option "+letter+".");
    });
    const answer=clean(raw.correct_answer??raw.answer??raw.answer_key).toUpperCase();
    if(!LETTERS.includes(answer))throw new Error("Question "+(index+1)+" must have correct_answer A, B, C or D.");
    const image=clean(raw.image_url);
    if(image&&!/^https:\/\//i.test(image))throw new Error("Question "+(index+1)+" has an image URL that is not HTTPS.");
    const subject=clean(raw.subject)||clean(defaultSubject);
    if(!subject)throw new Error("Question "+(index+1)+" is missing its subject.");
    if(clean(defaultSubject)&&subject!==clean(defaultSubject))throw new Error("Question "+(index+1)+" subject does not match the assessment subject.");
    const year=raw.exam_year===undefined||raw.exam_year===null||raw.exam_year===""?null:Number(raw.exam_year);
    if(year!==null&&(!Number.isInteger(year)||year<1900||year>2200))throw new Error("Question "+(index+1)+" has an invalid exam year.");
    return {
      subject,
      topic:clean(raw.topic),
      exam_type:clean(raw.exam_type),
      exam_year:year,
      question_text:questionText,
      option_a:options.A,
      option_b:options.B,
      option_c:options.C,
      option_d:options.D,
      correct_answer:answer,
      explanation:clean(raw.explanation),
      image_url:image||null,
      is_practice:false
    };
  }
  function parse(input,defaultSubject){
    let payload=input;
    if(typeof input==="string"){
      try{payload=JSON.parse(input)}catch(_){throw new Error("The selected file is not valid JSON.")}
    }
    const questions=Array.isArray(payload)?payload:payload&&Array.isArray(payload.questions)?payload.questions:null;
    if(!questions)throw new Error("File must contain a questions array.");
    if(!questions.length)throw new Error("The question file is empty.");
    return questions.map((q,i)=>normalizeQuestion(q,i,defaultSubject));
  }
  const api={parse,normalizeQuestion};
  if(typeof module!=="undefined"&&module.exports)module.exports=api;
  root.LOGOSTestQuestionImport=api;
})(typeof window!=="undefined"?window:globalThis);
