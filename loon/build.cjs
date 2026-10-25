const fs=require('node:fs'),path=require('node:path');
const root=__dirname;
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const vendor=['core','enc-base64','cipher-core','mode-ecb','aes'].map(n=>read('vendor/'+n+'.js')).join('\n;\n');
for(const name of ['wmbwc','xxyx'])fs.writeFileSync(path.join(root,'scripts',name+'.js'),(name==='wmbwc'?'/* Bundled CryptoJS 4.2.0, MIT. See vendor/LICENSE. */\n'+vendor+'\n;\n':'')+read('src/runtime.js')+'\n'+read('src/'+name+'.js'));
