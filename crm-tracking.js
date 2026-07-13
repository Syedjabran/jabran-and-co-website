/* ============================================================================
   JABRAN & CO. CRM — crm-tracking.js · MILESTONE TRACKING PANEL (staff)
   Requires: migration 020 · supabase-client.js
   Include on crm-orders.html (after crm-rm.js):
       <script src="crm-tracking.js"></script>
   Injects a Milestone Tracking section into the order modal: weighted
   progress bar, delay banner, expected/revised completion, next milestone,
   full milestone editor (start/complete/skip, due dates, client updates,
   internal notes, visibility) and plan generation from a service template.
   All maths, guards and notifications run in Postgres (migration 020).
============================================================================ */
(function () {
  'use strict';
  if (typeof window === 'undefined') return;

  function esc(s){ var d=document.createElement('div'); d.textContent=s==null?'':String(s); return d.innerHTML; }
  function el(h){ var d=document.createElement('div'); d.innerHTML=h.trim(); return d.firstChild; }

  var ST={pending:['PENDING','var(--muted,#9C9690)'], in_progress:['IN PROGRESS','var(--gold-light,#E4C98A)'],
          completed:['COMPLETED','#5cc9b4'], skipped:['SKIPPED','var(--muted,#9C9690)'], blocked:['BLOCKED','#e57368']};
  var templates=null;

  async function render(form){
    var mk=form.querySelector('.jco-custom');
    if(!mk || mk.dataset.module!=='orders') return;
    var idf=document.getElementById(mk.dataset.idfield||'or-id');
    var rid=idf?String(idf.value||'').trim():'';

    var host=form.querySelector('.jtr-host');
    if(!host){
      host=el('<div class="jtr-host" style="margin-top:18px; border-top:1px solid rgba(198,165,90,0.22); padding-top:14px;"></div>');
      var anchor=form.querySelector('.jrm-host')||form.querySelector('.jco-extras-host');
      if(anchor) form.insertBefore(host, anchor); else form.appendChild(host);
    }
    host.innerHTML='<div style="font-family:\'IBM Plex Mono\',monospace; font-size:10px; letter-spacing:0.2em; text-transform:uppercase; color:var(--gold,#C6A55A); margin-bottom:8px;">Milestone Tracking</div>'+
      '<div class="jtr-body" style="font-size:13px; color:var(--muted,#9C9690);">Loading…</div>';
    var body=host.querySelector('.jtr-body');
    if(!rid){ body.textContent='Save the order first — the tracking plan generates automatically on creation.'; return; }

    var [t, ms]=await Promise.all([
      sb.from('crm_order_tracking').select('*').eq('order_id',rid).maybeSingle(),
      sb.from('crm_order_milestones').select('*').eq('order_id',rid).order('sequence_number')
    ]);
    var track=t.data, rows=ms.data||[];

    /* ------- no plan yet: offer generation ------- */
    if(!rows.length){
      if(!templates){
        var tp=await sb.from('crm_tracking_templates').select('id,service_code,template_name')
                 .eq('is_active',true).order('template_name');
        templates=tp.data||[];
      }
      body.innerHTML='<div style="margin-bottom:8px;">No tracking plan exists for this order yet.</div>'+
        '<div style="display:flex; gap:8px; flex-wrap:wrap; align-items:center;">'+
        '<select class="jtr-tpl" style="padding:8px 10px; background:var(--bg-alt,#111820); border:1px solid rgba(198,165,90,0.22); color:var(--cream,#F5F3EF); border-radius:2px; font-size:12px;">'+
          '<option value="">Auto-detect from service</option>'+
          templates.map(function(x){return '<option value="'+x.id+'">'+esc(x.template_name)+'</option>';}).join('')+
        '</select>'+
        '<button type="button" class="jtr-gen" style="background:var(--gold,#C6A55A); color:#0a0a0b; border:none; padding:8px 16px; font-size:10px; letter-spacing:0.08em; text-transform:uppercase; cursor:pointer; border-radius:2px;">Generate Plan</button>'+
        '<span class="jtr-st" style="font-size:12px; color:var(--gold-light,#E4C98A);"></span></div>';
      body.querySelector('.jtr-gen').addEventListener('click', async function(){
        var st=body.querySelector('.jtr-st'); st.textContent='Generating…';
        var r=await sb.rpc('crm_generate_milestones',{p_order_id:rid,
          p_template_id:body.querySelector('.jtr-tpl').value||null});
        if(r.error){ st.textContent='Error: '+r.error.message; return; }
        render(form);
      });
      return;
    }

    /* ------- summary strip ------- */
    var prog=Math.round(Number(track&&track.progress_percentage||0));
    var exp=(track&&(track.revised_completion_date||track.expected_completion_date))||null;
    var summary=
      '<div style="margin-bottom:12px;">'+
        '<div style="display:flex; align-items:center; gap:10px; flex-wrap:wrap; margin-bottom:6px;">'+
          '<div style="flex:1; min-width:140px; height:7px; background:var(--bg-deep,#08111C); border:1px solid rgba(198,165,90,0.25); border-radius:2px; overflow:hidden;">'+
            '<div style="width:'+prog+'%; height:100%; background:linear-gradient(90deg,var(--gold,#C6A55A),var(--gold-light,#E4C98A));"></div></div>'+
          '<span style="font-family:\'IBM Plex Mono\',monospace; font-size:12px; color:var(--gold-light,#E4C98A);">'+prog+'%</span>'+
          (track&&track.is_delayed?'<span style="font-family:\'IBM Plex Mono\',monospace; font-size:10px; color:#e57368; border:1px solid #e57368; padding:2px 7px; border-radius:2px;">DELAYED</span>':'')+
        '</div>'+
        '<div style="font-size:12px; color:var(--muted,#9C9690); display:flex; gap:14px; flex-wrap:wrap; align-items:center;">'+
          (track&&track.next_milestone?'<span>Next: <span style="color:var(--cream,#F5F3EF);">'+esc(track.next_milestone)+'</span>'+(track.next_milestone_due_at?' · due '+esc(track.next_milestone_due_at):'')+'</span>':'')+
          '<span>Completion: <span style="color:var(--cream,#F5F3EF);">'+esc(exp||'—')+'</span></span>'+
          '<label style="display:flex; gap:6px; align-items:center;">Revise:'+
            '<input type="date" class="jtr-rev" value="'+esc(track&&track.revised_completion_date||'')+'" style="padding:4px 6px; background:var(--bg-alt,#111820); border:1px solid rgba(198,165,90,0.22); color:var(--cream,#F5F3EF); border-radius:2px; font-size:11px;"></label>'+
        '</div>'+
        (track&&track.is_delayed&&track.delay_reason?'<div style="font-size:11px; color:#e08a4a; margin-top:4px;">'+esc(track.delay_reason)+'</div>':'')+
      '</div>';

    /* ------- milestone rows ------- */
    var list=rows.map(function(m){
      var s=ST[m.status]||ST.pending;
      return '<div data-m="'+m.id+'" style="border-bottom:1px solid rgba(198,165,90,0.1); padding:7px 0;">'+
        '<div style="display:flex; gap:8px; align-items:center; flex-wrap:wrap;">'+
          '<span style="font-family:\'IBM Plex Mono\',monospace; font-size:10px; color:var(--muted,#9C9690); width:18px;">'+m.sequence_number+'</span>'+
          '<span style="flex:1; min-width:130px; font-size:13px; color:'+(m.status==='completed'?'var(--muted,#9C9690)':'var(--cream,#F5F3EF)')+';">'+esc(m.milestone_label)+
            (m.evidence_required?' <span title="Evidence required" style="color:var(--gold,#C6A55A); font-size:10px;">◈</span>':'')+
            (!m.client_visible?' <span style="font-size:9px; color:var(--muted,#9C9690);">INTERNAL</span>':'')+'</span>'+
          '<span style="font-family:\'IBM Plex Mono\',monospace; font-size:9px; letter-spacing:0.06em; border:1px solid '+s[1]+'; color:'+s[1]+'; padding:2px 6px; border-radius:2px;">'+s[0]+'</span>'+
          '<input type="date" data-f="planned_due_at" value="'+esc(m.planned_due_at||'')+'" style="padding:3px 5px; background:var(--bg-alt,#111820); border:1px solid rgba(198,165,90,0.22); color:var(--cream,#F5F3EF); border-radius:2px; font-size:11px;">'+
          (m.status==='pending'?'<button type="button" data-a="start" class="jtr-b">Start</button>':'')+
          (m.status!=='completed'&&m.status!=='skipped'?'<button type="button" data-a="complete" class="jtr-b">Complete</button>':'')+
          (m.status==='pending'?'<button type="button" data-a="skip" class="jtr-b">Skip</button>':'')+
          '<button type="button" data-a="more" class="jtr-b">▾</button>'+
        '</div>'+
        '<div class="jtr-more" style="display:none; padding:8px 0 4px 26px;">'+
          '<label style="display:block; font-size:10px; text-transform:uppercase; letter-spacing:0.08em; color:var(--muted,#9C9690); margin-bottom:3px;">Client-facing update</label>'+
          '<textarea data-f="client_update" style="width:100%; min-height:44px; padding:7px 9px; background:var(--bg-alt,#111820); border:1px solid rgba(198,165,90,0.22); color:var(--cream,#F5F3EF); border-radius:2px; font-size:12px; resize:vertical;">'+esc(m.client_update||'')+'</textarea>'+
          '<label style="display:block; font-size:10px; text-transform:uppercase; letter-spacing:0.08em; color:var(--muted,#9C9690); margin:8px 0 3px;">Internal notes</label>'+
          '<textarea data-f="internal_notes" style="width:100%; min-height:44px; padding:7px 9px; background:var(--bg-alt,#111820); border:1px solid rgba(198,165,90,0.22); color:var(--cream,#F5F3EF); border-radius:2px; font-size:12px; resize:vertical;">'+esc(m.internal_notes||'')+'</textarea>'+
          '<div style="display:flex; gap:10px; align-items:center; margin-top:8px; flex-wrap:wrap;">'+
            '<label style="font-size:11px; color:var(--muted,#9C9690); display:flex; gap:5px; align-items:center;"><input type="checkbox" data-f="client_visible" '+(m.client_visible?'checked':'')+'> Client visible</label>'+
            '<input data-f="delay_reason" placeholder="Delay reason (if any)" value="'+esc(m.delay_reason||'')+'" style="flex:1; min-width:150px; padding:6px 9px; background:var(--bg-alt,#111820); border:1px solid rgba(198,165,90,0.22); color:var(--cream,#F5F3EF); border-radius:2px; font-size:12px;">'+
            '<button type="button" data-a="save" class="jtr-b" style="border-color:var(--gold,#C6A55A);">Save Details</button>'+
          '</div>'+
        '</div></div>';
    }).join('');

    body.innerHTML=summary+
      '<style>.jtr-b{background:none;border:1px solid rgba(198,165,90,0.3);color:var(--gold-light,#E4C98A);font-size:10px;padding:3px 8px;cursor:pointer;border-radius:2px;}</style>'+
      '<div>'+list+'</div><div class="jtr-st" style="font-size:12px; color:var(--gold-light,#E4C98A); margin-top:6px;"></div>';
    var st=body.querySelector('.jtr-st');

    body.querySelector('.jtr-rev').addEventListener('change', async function(){
      var r=await sb.from('crm_order_tracking').update({revised_completion_date:this.value||null}).eq('order_id',rid);
      st.textContent=r.error?('Error: '+r.error.message):'Completion date revised.';
    });

    body.querySelectorAll('[data-m]').forEach(function(row){
      var mid=row.dataset.m;
      row.querySelectorAll('[data-a]').forEach(function(b){
        b.addEventListener('click', async function(){
          if(b.dataset.a==='more'){
            var mr=row.querySelector('.jtr-more');
            mr.style.display=mr.style.display==='none'?'block':'none'; return;
          }
          var patch={};
          if(b.dataset.a==='start')    patch.status='in_progress';
          if(b.dataset.a==='skip')     patch.status='skipped';
          if(b.dataset.a==='complete') patch.status='completed';
          if(b.dataset.a==='save'){
            patch.client_update  = row.querySelector('[data-f="client_update"]').value.trim()||null;
            patch.internal_notes = row.querySelector('[data-f="internal_notes"]').value.trim()||null;
            patch.delay_reason   = row.querySelector('[data-f="delay_reason"]').value.trim()||null;
            patch.client_visible = row.querySelector('[data-f="client_visible"]').checked;
          }
          st.textContent='Saving…';
          var r=await sb.from('crm_order_milestones').update(patch).eq('id',mid);
          if(r.error){ st.textContent='Error: '+r.error.message; return; }
          st.textContent='Saved.';
          if(b.dataset.a!=='save') render(form);
        });
      });
      row.querySelector('input[data-f="planned_due_at"]').addEventListener('change', async function(){
        var r=await sb.from('crm_order_milestones').update({planned_due_at:this.value||null}).eq('id',mid);
        st.textContent=r.error?('Error: '+r.error.message):'Due date updated.';
        if(!r.error) render(form);
      });
    });
  }

  function watch(){
    if(typeof sb==='undefined') return;
    document.querySelectorAll('.crm-modal-bg').forEach(function(m){
      if(m._jtrWatched) return; m._jtrWatched=true;
      new MutationObserver(function(){
        var visible=m.style.display&&m.style.display!=='none';
        if(!visible) return;
        var form=m.querySelector('form#order-form'); if(!form) return;
        setTimeout(function(){ render(form).catch(function(){}); },500);
      }).observe(m,{attributes:true,attributeFilter:['style','class']});
    });
  }
  document.addEventListener('DOMContentLoaded', function(){ watch(); setTimeout(watch,1500); });
})();
