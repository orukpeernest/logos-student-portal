const assert=require("node:assert/strict");
const importer=require("./test-question-import.js");
const valid={subject:"Physics",question_text:"What is force?",options:{A:"Push",B:"Pull",C:"Both",D:"Neither"},correct_answer:"C",explanation:"A force can push or pull."};
const parsed=importer.parse({questions:[valid]});
assert.equal(parsed.length,1);
assert.equal(parsed[0].is_practice,false);
assert.equal(parsed[0].option_a,"Push");
assert.equal(parsed[0].correct_answer,"C");
assert.equal(parsed[0].explanation,"A force can push or pull.");
assert.equal(importer.parse([{
  question:"Which is a unit of energy?",option_a:"Joule",option_b:"Watt",option_c:"Newton",option_d:"Pascal",answer:"A"
}],"Physics")[0].subject,"Physics");
assert.throws(()=>importer.parse({questions:[]}),/empty/);
assert.throws(()=>importer.parse({questions:[{...valid,correct_answer:"E"}]}),/correct_answer/);
assert.throws(()=>importer.parse({questions:[{...valid,option_b:""}]}),/option B/);
assert.throws(()=>importer.parse({questions:[{...valid,image_url:"http://example.com/x.png"}]}),/HTTPS/);
assert.throws(()=>importer.parse("{bad json"),/valid JSON/);
console.log("Test question import checks passed.");
