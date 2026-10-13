import React, { useState, useEffect, useMemo, useRef } from 'react';
import { 
  Plus, 
  Trash2, 
  Save, 
  AlertCircle, 
  CheckCircle2, 
  Terminal, 
  Search, 
  ChevronDown,
  FileText
} from 'lucide-react';

// MOCK DATA: Chart of Accounts grouped by Classification
const ACCOUNT_CLASSIFICATIONS = [
  {
    group: '1 - Aset',
    accounts: [
      { id: '1010', name: 'Kas Utama' },
      { id: '1020', name: 'Kas Kecil' },
      { id: '1110', name: 'Bank BCA' },
      { id: '1120', name: 'Bank Mandiri' }
    ]
  },
  {
    group: '2 - Kewajiban',
    accounts: [
      { id: '2010', name: 'Hutang Usaha' },
      { id: '2020', name: 'Hutang Gaji' },
      { id: '2110', name: 'Hutang Pajak PPN' }
    ]
  },
  {
    group: '3 - Ekuitas',
    accounts: [
      { id: '3010', name: 'Modal Disetor' },
      { id: '3020', name: 'Laba Ditahan' }
    ]
  },
  {
    group: '4 - Pendapatan',
    accounts: [
      { id: '4010', name: 'Pendapatan Jasa' },
      { id: '4020', name: 'Pendapatan Lain-lain' }
    ]
  },
  {
    group: '5 - Beban',
    accounts: [
      { id: '5010', name: 'Beban Gaji & Tunjangan' },
      { id: '5020', name: 'Beban Operasional Kantor' },
      { id: '5030', name: 'Beban Pemasaran' },
      { id: '5040', name: 'Beban Administrasi Bank' }
    ]
  }
];

// Helper: Format IDR
const formatIDR = (num) => {
  return new Intl.NumberFormat('id-ID', { style: 'currency', currency: 'IDR', minimumFractionDigits: 0 }).format(num || 0);
};

const SearchableAccountSelect = ({ value, onChange, id }) => {
  const [isOpen, setIsOpen] = useState(false);
  const [search, setSearch] = useState('');
  const wrapperRef = useRef(null);

  // Close dropdown when clicking outside
  useEffect(() => {
    function handleClickOutside(event) {
      if (wrapperRef.current && !wrapperRef.current.contains(event.target)) {
        setIsOpen(false);
      }
    }
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  // Flatten and search accounts
  const filteredGroups = useMemo(() => {
    if (!search) return ACCOUNT_CLASSIFICATIONS;
    const lowerSearch = search.toLowerCase();
    return ACCOUNT_CLASSIFICATIONS.map(group => ({
      ...group,
      accounts: group.accounts.filter(a => 
        a.id.includes(lowerSearch) || a.name.toLowerCase().includes(lowerSearch)
      )
    })).filter(group => group.accounts.length > 0);
  }, [search]);

  // Find selected account text
  const selectedAccount = useMemo(() => {
    for (const group of ACCOUNT_CLASSIFICATIONS) {
      const acc = group.accounts.find(a => a.id === value);
      if (acc) return `${acc.id} - ${acc.name}`;
    }
    return 'Pilih Akun...';
  }, [value]);

  return (
    <div className="relative" ref={wrapperRef}>
      <div 
        className="flex items-center justify-between w-full p-1.5 bg-white border border-slate-300 rounded text-sm cursor-pointer hover:border-blue-500 focus-within:ring-1 focus-within:ring-blue-500"
        onClick={() => setIsOpen(!isOpen)}
      >
        <span className={`truncate ${!value ? 'text-slate-400' : 'text-slate-800'}`}>
          {selectedAccount}
        </span>
        <ChevronDown size={14} className="text-slate-400 flex-shrink-0" />
      </div>

      {isOpen && (
        <div className="absolute z-50 w-full mt-1 bg-white border border-slate-200 rounded shadow-xl max-h-60 flex flex-col">
          <div className="p-2 border-b border-slate-100 sticky top-0 bg-white">
            <div className="relative">
              <Search size={14} className="absolute left-2 top-2 text-slate-400" />
              <input
                type="text"
                autoFocus
                placeholder="Cari nama/kode akun..."
                className="w-full pl-7 pr-2 py-1 text-sm border border-slate-200 rounded focus:outline-none focus:border-blue-500"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
              />
            </div>
          </div>
          <div className="overflow-y-auto flex-1 p-1">
            {filteredGroups.length === 0 ? (
              <div className="p-2 text-sm text-slate-400 text-center">Akun tidak ditemukan</div>
            ) : (
              filteredGroups.map((group, idx) => (
                <div key={idx} className="mb-2 last:mb-0">
                  <div className="px-2 py-1 text-xs font-bold text-slate-500 bg-slate-50">
                    {group.group}
                  </div>
                  {group.accounts.map(acc => (
                    <div
                      key={acc.id}
                      className="px-2 py-1.5 text-sm cursor-pointer hover:bg-blue-50 text-slate-700 hover:text-blue-700"
                      onClick={() => {
                        onChange(acc.id);
                        setIsOpen(false);
                        setSearch('');
                      }}
                    >
                      <span className="font-mono text-xs mr-2">{acc.id}</span>
                      {acc.name}
                    </div>
                  ))}
                </div>
              ))
            )}
          </div>
        </div>
      )}
    </div>
  );
};

export default function CashDisbursementVoucher() {
  const logContainerRef = useRef(null);

  // 1. Audit Log State
  const [logs, setLogs] = useState([]);
  
  const addLog = (action, detail) => {
    const timestamp = new Date().toLocaleTimeString('id-ID', { hour12: false });
    setLogs(prev => [...prev, { id: Date.now() + Math.random(), timestamp, action, detail }]);
  };

  // 2. Form State
  const [header, setHeader] = useState({
    voucherNo: 'BK-' + new Date().getFullYear() + '-' + String(Math.floor(Math.random() * 9999)).padStart(4, '0'),
    date: new Date().toISOString().split('T')[0],
    payee: '',
    notes: ''
  });

  const [entries, setEntries] = useState([
    { id: 'row-1', accountId: '', description: '', debit: '', credit: '' },
    { id: 'row-2', accountId: '', description: '', debit: '', credit: '' }
  ]);

  const [isSubmitting, setIsSubmitting] = useState(false);
  const [docStatus, setDocStatus] = useState('DRAFT'); // DRAFT | SUBMITTED

  // Initial Load Log
  useEffect(() => {
    addLog('SYSTEM_INIT', 'Modul Entri Voucher Kas Keluar dimuat. Mode: Compact Layout.');
  }, []);

  // Auto-scroll audit log
  useEffect(() => {
    if (logContainerRef.current) {
      logContainerRef.current.scrollTop = logContainerRef.current.scrollHeight;
    }
  }, [logs]);

  // 3. Derived State & Validations
  const { totalDebit, totalCredit, isBalanced, hasConflict, conflictRows } = useMemo(() => {
    let td = 0;
    let tc = 0;
    let conflicts = [];

    entries.forEach(entry => {
      const d = Number(entry.debit) || 0;
      const c = Number(entry.credit) || 0;
      td += d;
      tc += c;

      // RULE 2: Anti-duplication on same line
      if (d > 0 && c > 0) {
        conflicts.push(entry.id);
      }
    });

    return {
      totalDebit: td,
      totalCredit: tc,
      // RULE 1: Zero-Discrepancy
      isBalanced: td === tc && td > 0,
      hasConflict: conflicts.length > 0,
      conflictRows: conflicts
    };
  }, [entries]);

  const isFormValid = isBalanced && !hasConflict && header.payee.trim() !== '';

  const handleHeaderChange = (e) => {
    const { name, value } = e.target;
    setHeader(prev => ({ ...prev, [name]: value }));
  };

  const handleEntryChange = (id, field, value) => {
    setEntries(prev => prev.map(entry => {
      if (entry.id === id) {
        return { ...entry, [field]: value };
      }
      return entry;
    }));
  };

  const addRow = () => {
    setEntries(prev => [...prev, { id: `row-${Date.now()}`, accountId: '', description: '', debit: '', credit: '' }]);
    addLog('ACTION', 'Menambah baris jurnal baru.');
  };

  const removeRow = (id) => {
    if (entries.length <= 2) {
      addLog('WARNING', 'Gagal menghapus: Minimal 2 baris jurnal diperlukan.');
      return;
    }
    setEntries(prev => prev.filter(e => e.id !== id));
    addLog('ACTION', `Menghapus baris jurnal (ID: ${id}).`);
  };

  const handleSubmit = () => {
    if (!isFormValid) return;
    
    setIsSubmitting(true);
    addLog('PROCESS', `Menginisiasi posting jurnal ke database (Supabase). Memvalidasi ${entries.length} baris...`);

    // Simulasi Network Request ke Supabase
    setTimeout(() => {
      setIsSubmitting(false);
      setDocStatus('POSTED');
      addLog('SUCCESS', `Jurnal ${header.voucherNo} berhasil diposting. Total Transaksi: ${formatIDR(totalDebit)}`);
    }, 1500);
  };

  const handleReset = () => {
    setDocStatus('DRAFT');
    setHeader({ ...header, payee: '', notes: '' });
    setEntries([
      { id: `row-${Date.now()}`, accountId: '', description: '', debit: '', credit: '' },
      { id: `row-${Date.now()+1}`, accountId: '', description: '', debit: '', credit: '' }
    ]);
    addLog('RESET', 'Formulir dikembalikan ke status awal.');
  };

  return (
    // Compact Layout Container: 100vh, hidden overflow on body, flex column
    <div className="h-screen w-full bg-slate-100 flex flex-col font-sans overflow-hidden">
      
      {/* Top Navbar */}
      <div className="h-14 bg-slate-900 text-white flex items-center justify-between px-6 flex-shrink-0 shadow-md z-10">
        <div className="flex items-center space-x-3">
          <FileText className="text-blue-400" size={24} />
          <div>
            <h1 className="text-base font-bold leading-tight">Sistem Jurnal Kas Keluar</h1>
            <p className="text-xs text-slate-400 leading-tight">Modul Entri Akuntansi - Zero Discrepancy</p>
          </div>
        </div>
        <div className="flex items-center space-x-4">
          <div className="flex flex-col text-right">
            <span className="text-xs text-slate-400">Status Dokumen</span>
            <span className={`text-sm font-bold ${docStatus === 'POSTED' ? 'text-green-400' : 'text-amber-400'}`}>
              {docStatus}
            </span>
          </div>
        </div>
      </div>

      {/* Main Content Area: Scrollable internally if needed, but designed to fit */}
      <div className="flex-1 flex flex-col p-4 gap-4 min-h-0">
        
        {/* SECTION 1: Document Header Form */}
        <div className="bg-white p-4 rounded-lg shadow-sm border border-slate-200 flex-shrink-0">
          <div className="grid grid-cols-4 gap-4">
            <div>
              <label className="block text-xs font-semibold text-slate-600 mb-1">No. Voucher</label>
              <input 
                type="text" 
                value={header.voucherNo} 
                disabled 
                className="w-full p-1.5 text-sm bg-slate-100 border border-slate-200 rounded text-slate-500 font-mono"
              />
            </div>
            <div>
              <label className="block text-xs font-semibold text-slate-600 mb-1">Tanggal Transaksi</label>
              <input 
                type="date" 
                name="date"
                value={header.date}
                onChange={handleHeaderChange}
                disabled={docStatus === 'POSTED'}
                className="w-full p-1.5 text-sm border border-slate-300 rounded focus:border-blue-500 focus:ring-1 focus:ring-blue-500 outline-none transition-all"
              />
            </div>
            <div>
              <label className="block text-xs font-semibold text-slate-600 mb-1">Dibayarkan Kepada <span className="text-red-500">*</span></label>
              <input 
                type="text" 
                name="payee"
                value={header.payee}
                onChange={handleHeaderChange}
                disabled={docStatus === 'POSTED'}
                placeholder="Nama Vendor / Karyawan"
                className="w-full p-1.5 text-sm border border-slate-300 rounded focus:border-blue-500 focus:ring-1 focus:ring-blue-500 outline-none transition-all"
              />
            </div>
            <div>
              <label className="block text-xs font-semibold text-slate-600 mb-1">Keterangan Umum</label>
              <input 
                type="text" 
                name="notes"
                value={header.notes}
                onChange={handleHeaderChange}
                disabled={docStatus === 'POSTED'}
                placeholder="Deskripsi transaksi..."
                className="w-full p-1.5 text-sm border border-slate-300 rounded focus:border-blue-500 focus:ring-1 focus:ring-blue-500 outline-none transition-all"
              />
            </div>
          </div>
        </div>

        {}
        {/* SECTION 2: Journal Entries Table (Flex-1 allows it to grow and scroll internally) */}
        <div className="flex-1 bg-white border border-slate-200 rounded-lg shadow-sm flex flex-col min-h-0">
          <div className="bg-slate-50 border-b border-slate-200 p-2 flex justify-between items-center flex-shrink-0">
            <h2 className="text-sm font-bold text-slate-700 ml-2">Detail Jurnal / Distribusi Akun</h2>
            {docStatus !== 'POSTED' && (
              <button 
                onClick={addRow}
                className="flex items-center text-xs font-semibold bg-white border border-slate-300 text-slate-700 px-3 py-1.5 rounded hover:bg-slate-50 transition-colors shadow-sm"
              >
                <Plus size={14} className="mr-1" /> Tambah Baris
              </button>
            )}
          </div>
          
          <div className="flex-1 overflow-auto">
            <table className="w-full text-left border-collapse">
              <thead className="bg-white sticky top-0 shadow-sm z-10">
                <tr>
                  <th className="p-2 text-xs font-semibold text-slate-500 border-b w-[250px]">Kode/Nama Akun</th>
                  <th className="p-2 text-xs font-semibold text-slate-500 border-b">Uraian Transaksi</th>
                  <th className="p-2 text-xs font-semibold text-slate-500 border-b w-[180px] text-right">Debit (Rp)</th>
                  <th className="p-2 text-xs font-semibold text-slate-500 border-b w-[180px] text-right">Kredit (Rp)</th>
                  <th className="p-2 text-xs font-semibold text-slate-500 border-b w-12 text-center">Aksi</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {entries.map((entry, index) => {
                  const isConflictRow = conflictRows.includes(entry.id);
                  return (
                    <tr key={entry.id} className={`hover:bg-slate-50 ${isConflictRow ? 'bg-red-50' : ''}`}>
                      <td className="p-2 align-top">
                        <SearchableAccountSelect 
                          value={entry.accountId}
                          onChange={(val) => handleEntryChange(entry.id, 'accountId', val)}
                        />
                      </td>
                      <td className="p-2 align-top">
                        <input 
                          type="text" 
                          value={entry.description}
                          onChange={(e) => handleEntryChange(entry.id, 'description', e.target.value)}
                          disabled={docStatus === 'POSTED'}
                          placeholder="Opsional, uraian per baris"
                          className="w-full p-1.5 text-sm border border-slate-200 rounded focus:border-blue-500 outline-none"
                        />
                      </td>
                      <td className="p-2 align-top">
                        <input 
                          type="number" 
                          value={entry.debit}
                          onChange={(e) => handleEntryChange(entry.id, 'debit', e.target.value)}
                          disabled={docStatus === 'POSTED'}
                          placeholder="0"
                          className={`w-full p-1.5 text-sm text-right font-mono border rounded outline-none ${isConflictRow ? 'border-red-400 bg-red-100/50' : 'border-slate-200 focus:border-blue-500'}`}
                        />
                      </td>
                      <td className="p-2 align-top">
                        <input 
                          type="number" 
                          value={entry.credit}
                          onChange={(e) => handleEntryChange(entry.id, 'credit', e.target.value)}
                          disabled={docStatus === 'POSTED'}
                          placeholder="0"
                          className={`w-full p-1.5 text-sm text-right font-mono border rounded outline-none ${isConflictRow ? 'border-red-400 bg-red-100/50' : 'border-slate-200 focus:border-blue-500'}`}
                        />
                      </td>
                      <td className="p-2 align-top text-center">
                        <button 
                          onClick={() => removeRow(entry.id)}
                          disabled={docStatus === 'POSTED'}
                          className="p-1.5 text-slate-400 hover:text-red-500 hover:bg-red-50 rounded disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
                        >
                          <Trash2 size={16} />
                        </button>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>

          {/* Table Footer / Summary (Sticky inside table container) */}
          <div className="bg-slate-50 border-t border-slate-200 p-3 flex-shrink-0 flex justify-between items-center">
            
            {/* Rule Validations Feedback */}
            <div className="flex-1">
              {hasConflict ? (
                <div className="flex items-center text-xs text-red-600 font-semibold bg-red-100 p-1.5 rounded w-max">
                  <AlertCircle size={14} className="mr-1.5" />
                  Aturan Dilanggar: Ditemukan isian Debit & Kredit pada baris yang sama.
                </div>
              ) : !header.payee ? (
                <div className="flex items-center text-xs text-amber-600 font-semibold">
                  <AlertCircle size={14} className="mr-1.5" /> Lengkapi field 'Dibayarkan Kepada'.
                </div>
              ) : isBalanced ? (
                <div className="flex items-center text-xs text-green-600 font-semibold bg-green-100 p-1.5 rounded w-max px-3">
                  <CheckCircle2 size={14} className="mr-1.5" /> Jurnal Balanced. Siap diposting.
                </div>
              ) : (
                <div className="flex items-center text-xs text-red-600 font-semibold bg-red-100 p-1.5 rounded w-max px-3">
                  <AlertCircle size={14} className="mr-1.5" /> Jurnal Belum Balance. Selisih: {formatIDR(Math.abs(totalDebit - totalCredit))}
                </div>
              )}
            </div>

            {/* Totals Calculation */}
            <div className="flex gap-6 pr-12">
              <div className="text-right">
                <div className="text-[10px] uppercase text-slate-500 font-bold tracking-wider">Total Debit</div>
                <div className={`text-lg font-mono font-bold ${totalDebit !== totalCredit ? 'text-red-600' : 'text-slate-800'}`}>
                  {formatIDR(totalDebit)}
                </div>
              </div>
              <div className="text-right">
                <div className="text-[10px] uppercase text-slate-500 font-bold tracking-wider">Total Kredit</div>
                <div className={`text-lg font-mono font-bold ${totalDebit !== totalCredit ? 'text-red-600' : 'text-slate-800'}`}>
                  {formatIDR(totalCredit)}
                </div>
              </div>
            </div>
            
            {/* Action Buttons */}
            <div className="pl-4 border-l border-slate-200 flex space-x-2">
              {docStatus === 'POSTED' ? (
                <button 
                  onClick={handleReset}
                  className="flex items-center px-4 py-2 bg-slate-200 text-slate-700 text-sm font-bold rounded hover:bg-slate-300 transition-colors"
                >
                  Buat Jurnal Baru
                </button>
              ) : (
                <button
                  onClick={handleSubmit}
                  disabled={!isFormValid || isSubmitting}
                  className={`
                    flex items-center px-5 py-2 rounded text-sm font-bold transition-all
                    ${isFormValid && !isSubmitting 
                      ? 'bg-slate-900 text-white hover:bg-slate-800 shadow-md hover:shadow-lg' 
                      : 'bg-slate-200 text-slate-400 cursor-not-allowed'}
                  `}
                >
                  {isSubmitting ? (
                    <span className="flex items-center"><div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin mr-2"></div> Memproses...</span>
                  ) : (
                    <><Save size={16} className="mr-2" /> Posting Jurnal</>
                  )}
                </button>
              )}
            </div>
          </div>
        </div>

        {}
        {/* SECTION 3: System Audit Log */}
        <div className="h-32 bg-slate-900 rounded-lg shadow-inner flex flex-col flex-shrink-0 border border-slate-800">
          <div className="px-3 py-1.5 bg-slate-950 border-b border-slate-800 rounded-t-lg flex items-center justify-between">
            <div className="flex items-center text-slate-400 text-xs font-mono">
              <Terminal size={14} className="mr-2 text-green-400" /> System Audit Log
            </div>
            <div className="text-[10px] text-slate-500 font-mono">Mock Supabase DB Connect</div>
          </div>
          <div ref={logContainerRef} className="flex-1 overflow-y-auto p-2 font-mono text-[11px] leading-relaxed">
            {logs.map(log => (
              <div key={log.id} className="flex space-x-3 mb-1 group">
                <span className="text-slate-500 w-16 flex-shrink-0">[{log.timestamp}]</span>
                <span className={`w-20 flex-shrink-0 font-semibold
                  ${log.action === 'SYSTEM_INIT' ? 'text-blue-400' : ''}
                  ${log.action === 'ACTION' ? 'text-slate-300' : ''}
                  ${log.action === 'WARNING' ? 'text-amber-400' : ''}
                  ${log.action === 'PROCESS' ? 'text-purple-400' : ''}
                  ${log.action === 'SUCCESS' ? 'text-green-400' : ''}
                  ${log.action === 'RESET' ? 'text-cyan-400' : ''}
                `}>
                  {log.action.padEnd(10, ' ')}
                </span>
                <span className="text-slate-300 group-hover:text-white transition-colors">{log.detail}</span>
              </div>
            ))}
          </div>
        </div>

      </div>
    </div>
  );
}