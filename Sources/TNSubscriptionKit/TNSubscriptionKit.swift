// The building blocks shared by the engines that run StoreKit 2 themselves (Core, Adapty,
// Qonversion). Each of those engines re-exports this module, so an app never imports it directly.
// (Các khối dùng chung cho những engine tự chạy StoreKit 2 — Core, Adapty, Qonversion. Mỗi engine
// đó re-export module này, nên app không bao giờ phải import trực tiếp.)
//
// Rule: code goes here only when it is the same in every one of those engines. Anything that reads
// or writes a vendor SDK's types stays in that engine.
// (Quy tắc: code chỉ được đặt ở đây khi nó giống nhau ở mọi engine đó. Mọi thứ đọc/ghi kiểu dữ liệu
// của SDK nhà cung cấp thì ở lại engine của nó.)
@_exported import TNSubscriptionShared
