import { faqItems } from '../data/faq';

const Faq = () => (
  <section className="faq">
    <div className="container">
      <div className="section-title">
        <span className="eyebrow">FAQs</span>
        <h2>Answers for the operations team.</h2>
      </div>
      <div className="faq-grid">
        {faqItems.map((item) => (
          <article key={item.title}>
            <h3>{item.title}</h3>
            <p>{item.body}</p>
          </article>
        ))}
      </div>
    </div>
  </section>
);

export default Faq;
