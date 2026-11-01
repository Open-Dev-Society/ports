import subprocess,re,os
top=subprocess.run(['top','-l','1','-stats','pid,mem'],capture_output=True,text=True).stdout
mem={}
for l in top.splitlines():
    m=re.match(r'\s*(\d+)\*?\s+([\d.]+)([BKMG])',l)
    if m: mem[int(m[1])]=float(m[2])*{'B':1/1048576,'K':1/1024,'M':1,'G':1024}[m[3]]
ls=subprocess.run(['lsof','-nP','-iTCP','-sTCP:LISTEN','-F','pcn'],capture_output=True,text=True).stdout
seen={};pid=None
for l in ls.splitlines():
    if l[0]=='p':pid=int(l[1:])
    elif l[0]=='c':name=l[1:]
    elif l[0]=='n':
        seen.setdefault(pid,{'name':name,'ports':set(),'pub':False})
        a,p=l[1:].rsplit(':',1);seen[pid]['ports'].add(int(p))
        if a in('*','0.0.0.0','[::]'):seen[pid]['pub']=True
rows=[]
for p,d in seen.items():
    o=subprocess.run(['ps','-o','etime=,command=','-p',str(p)],capture_output=True,text=True).stdout.strip().split(None,1)
    cw=subprocess.run(f'lsof -a -d cwd -p {p} -Fn',shell=True,capture_output=True,text=True).stdout
    cwd=next((x[1:] for x in cw.splitlines() if x.startswith('n')),'')
    rows.append((mem.get(p,0),sorted(d['ports'])[:3],d['name'][:14],o[0] if o else '','open to network' if d['pub'] else 'local',cwd.replace(os.path.expanduser('~'),'~')[-44:]))
for r in sorted(rows,key=lambda r:-r[0]):print(f'{r[0]:7.0f} MB  {str(r[1]):22} {r[2]:15} up {r[3]:12} {r[4]:16} {r[5]}')
print(len(rows),'listening')
